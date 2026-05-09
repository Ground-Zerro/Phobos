import { drizzle } from 'drizzle-orm/libsql';
import { migrate as drizzleMigrate } from 'drizzle-orm/libsql/migrator';
import { createClient } from '@libsql/client';
import { readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import debug from 'debug';
import { eq, sql } from 'drizzle-orm';

import * as schema from './schema';
import { ClientService } from './repositories/client/service';
import { GeneralService } from './repositories/general/service';
import { UserService } from './repositories/user/service';
import { UserConfigService } from './repositories/userConfig/service';
import { InterfaceService } from './repositories/interface/service';
import { HooksService } from './repositories/hooks/service';
import { InstallLinkService } from './repositories/installLink/service';

const DB_DEBUG = debug('Database');

const client = createClient({ url: 'file:/etc/wireguard/wg-easy.db' });
const db = drizzle({ client, schema });

export async function connect() {
  await migrate();
  const dbService = new DBService(db);

  if (WG_INITIAL_ENV.ENABLED) {
    await initialSetup(dbService);
  }

  if (WG_ENV.DISABLE_IPV6) {
    DB_DEBUG('Warning: Disabling IPv6...');
    await disableIpv6(db);
  }

  return dbService;
}

class DBService {
  clients: ClientService;
  general: GeneralService;
  users: UserService;
  userConfigs: UserConfigService;
  interfaces: InterfaceService;
  hooks: HooksService;
  installLinks: InstallLinkService;

  constructor(db: DBType) {
    this.clients = new ClientService(db);
    this.general = new GeneralService(db);
    this.users = new UserService(db);
    this.userConfigs = new UserConfigService(db);
    this.interfaces = new InterfaceService(db);
    this.hooks = new HooksService(db);
    this.installLinks = new InstallLinkService(db);
  }
}

export type DBType = typeof db;
export type DBServiceType = DBService;

function resolveMigrationsFolder(): string {
  const candidates = [
    join(dirname(fileURLToPath(import.meta.url)), 'migrations'),
    '/app/server/database/migrations',
    join(process.cwd(), 'server/database/migrations'),
    join(process.cwd(), 'src/server/database/migrations'),
  ];
  const found = candidates.find((p) => {
    try { readdirSync(p); return true; } catch { return false; }
  });
  if (!found) {
    throw new Error(`migrations folder not found (tried: ${candidates.join(', ')})`);
  }
  return found;
}

async function hasTable(name: string): Promise<boolean> {
  const row = await db.run(
    sql`SELECT name FROM sqlite_master WHERE type = 'table' AND name = ${name}`,
  );
  return Array.isArray(row.rows) && row.rows.length > 0;
}

async function seedMigrationTracking() {
  await db.run(sql`
    CREATE TABLE IF NOT EXISTS __drizzle_migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      hash TEXT NOT NULL UNIQUE,
      created_at NUMERIC
    )
  `);
  await db.run(
    sql`INSERT OR IGNORE INTO __drizzle_migrations (hash, created_at) VALUES ('bootstrapped', ${Date.now()})`,
  );
  DB_DEBUG('Migration tracking seeded for bootstrapped database');
}

async function migrate() {
  await db.run(sql`PRAGMA journal_mode=WAL`);

  const migrationsFolder = resolveMigrationsFolder();

  const hasInterfaces = await hasTable('interfaces_table');
  const hasMigrations = await hasTable('__drizzle_migrations');

  if (hasInterfaces && !hasMigrations) {
    DB_DEBUG('Bootstrapped database detected: seeding migration tracking...');
    await seedMigrationTracking();
  }

  DB_DEBUG('Migrating database...');
  await drizzleMigrate(db, { migrationsFolder });
  DB_DEBUG('Migration complete');
}

async function initialSetup(db: DBServiceType) {
  const setup = await db.general.getSetupStep();

  if (setup.done) {
    DB_DEBUG('Setup already done. Skiping initial setup.');
    return;
  }

  if (WG_INITIAL_ENV.IPV4_CIDR && WG_INITIAL_ENV.IPV6_CIDR) {
    DB_DEBUG('Setting initial CIDR...');
    await db.interfaces.updateCidr({
      ipv4Cidr: WG_INITIAL_ENV.IPV4_CIDR,
      ipv6Cidr: WG_INITIAL_ENV.IPV6_CIDR,
    });
  }

  if (WG_INITIAL_ENV.DNS) {
    DB_DEBUG('Setting initial DNS...');
    await db.userConfigs.update({
      defaultDns: WG_INITIAL_ENV.DNS,
    });
  }

  if (WG_INITIAL_ENV.ALLOWED_IPS) {
    DB_DEBUG('Setting initial Allowed IPs...');
    await db.userConfigs.update({
      defaultAllowedIps: WG_INITIAL_ENV.ALLOWED_IPS,
    });
  }

  if (WG_INITIAL_ENV.USERNAME && WG_INITIAL_ENV.PASSWORD && WG_INITIAL_ENV.HOST) {
    DB_DEBUG('Creating initial user...');
    await db.users.create(WG_INITIAL_ENV.USERNAME, WG_INITIAL_ENV.PASSWORD);

    DB_DEBUG('Setting initial host...');
    await db.userConfigs.updateHost(WG_INITIAL_ENV.HOST);

    await db.general.setSetupStep(0);
  }
}

async function disableIpv6(db: DBType) {
  const postUpMatch =
    ' ip6tables -t nat -A POSTROUTING -s {{ipv6Cidr}} -o {{device}} -j MASQUERADE; ip6tables -A INPUT -p udp -m udp --dport {{port}} -j ACCEPT; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -A FORWARD -o wg0 -j ACCEPT;';
  const postDownMatch =
    ' ip6tables -t nat -D POSTROUTING -s {{ipv6Cidr}} -o {{device}} -j MASQUERADE; ip6tables -D INPUT -p udp -m udp --dport {{port}} -j ACCEPT; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -D FORWARD -o wg0 -j ACCEPT;';

  await db.transaction(async (tx) => {
    const hooks = await tx.query.hooks.findFirst({
      where: eq(schema.hooks.id, 'wg0'),
    });

    if (!hooks) {
      throw new Error('Hooks not found');
    }

    if (hooks.postUp.includes(postUpMatch)) {
      DB_DEBUG('Disabling IPv6 in Post Up hooks...');
      await tx
        .update(schema.hooks)
        .set({
          postUp: hooks.postUp.replace(postUpMatch, ''),
          postDown: hooks.postDown.replace(postDownMatch, ''),
        })
        .where(eq(schema.hooks.id, 'wg0'))
        .execute();
    } else {
      DB_DEBUG('IPv6 Post Up hooks already disabled, skipping...');
    }
    if (hooks.postDown.includes(postDownMatch)) {
      DB_DEBUG('Disabling IPv6 in Post Down hooks...');
      await tx
        .update(schema.hooks)
        .set({
          postUp: hooks.postUp.replace(postUpMatch, ''),
          postDown: hooks.postDown.replace(postDownMatch, ''),
        })
        .where(eq(schema.hooks.id, 'wg0'))
        .execute();
    } else {
      DB_DEBUG('IPv6 Post Down hooks already disabled, skipping...');
    }
  });
}
