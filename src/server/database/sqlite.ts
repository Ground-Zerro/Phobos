import { join } from 'node:path';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate as drizzleMigrate } from 'drizzle-orm/libsql/migrator';
import { createClient } from '@libsql/client';
import { eq, sql } from 'drizzle-orm';
import { createLogger } from '../utils/logger';

import * as schema from './schema';
import { DB_URL } from './url';
import { ClientService } from './repositories/client/service';
import { GeneralService } from './repositories/general/service';
import { UserService } from './repositories/user/service';
import { UserConfigService } from './repositories/userConfig/service';
import { InterfaceService } from './repositories/interface/service';
import { HooksService } from './repositories/hooks/service';
import { InstallLinkService } from './repositories/installLink/service';
import { ObfuscatorPresetService } from './repositories/obfuscatorPreset/service';
import { WarpService } from './repositories/warp/service';

const DB_DEBUG = createLogger('Database');

const client = createClient({ url: DB_URL });
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
  obfuscatorPresets: ObfuscatorPresetService;
  warp: WarpService;

  constructor(db: DBType) {
    this.clients = new ClientService(db);
    this.general = new GeneralService(db);
    this.users = new UserService(db);
    this.userConfigs = new UserConfigService(db);
    this.interfaces = new InterfaceService(db);
    this.hooks = new HooksService(db);
    this.installLinks = new InstallLinkService(db);
    this.obfuscatorPresets = new ObfuscatorPresetService(db);
    this.warp = new WarpService(db);
  }
}

export type DBType = typeof db;
export type DBTransaction = Parameters<Parameters<DBType['transaction']>[0]>[0];
export type DBExecutor = DBType | DBTransaction;
export type DBServiceType = DBService;

async function migrate() {
  await db.run(sql`PRAGMA journal_mode=WAL`);
  await db.run(sql`PRAGMA wal_autocheckpoint=1000`);
  await db.run(sql`PRAGMA wal_checkpoint(PASSIVE)`);

  DB_DEBUG('Migrating database...');
  await drizzleMigrate(db, {
    migrationsFolder: join(process.cwd(), 'server/database/migrations'),
  });
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

  if (
    WG_INITIAL_ENV.USERNAME &&
    WG_INITIAL_ENV.PASSWORD &&
    WG_INITIAL_ENV.HOST
  ) {
    DB_DEBUG('Creating initial user...');
    await db.users.create(WG_INITIAL_ENV.USERNAME, WG_INITIAL_ENV.PASSWORD);

    DB_DEBUG('Setting initial host...');
    await db.userConfigs.update({ host: WG_INITIAL_ENV.HOST });

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
      where: eq(schema.hooks.id, schema.WG_INTERFACE_NAME),
    });

    if (!hooks) {
      throw new Error('Hooks not found');
    }

    if (
      !hooks.postUp.includes(postUpMatch) &&
      !hooks.postDown.includes(postDownMatch)
    ) {
      DB_DEBUG('IPv6 hooks already disabled, skipping...');
      return;
    }

    DB_DEBUG('Disabling IPv6 in hooks...');
    await tx
      .update(schema.hooks)
      .set({
        postUp: hooks.postUp.replace(postUpMatch, ''),
        postDown: hooks.postDown.replace(postDownMatch, ''),
      })
      .where(eq(schema.hooks.id, schema.WG_INTERFACE_NAME))
      .execute();
  });
}
