import { eq, sql, or, like, and, isNotNull } from 'drizzle-orm';
import { containsCidr, parseCidr } from 'cidr-tools';
import { client } from './schema';
import type { ClientCreateType, ClientType, UpdateClientType } from './types';
import { Repository } from '#db/repository';
import type { DBExecutor, DBType } from '#db/sqlite';
import { WG_INTERFACE_NAME, userConfig, wgInterface } from '#db/schema';
import { resolvePreset } from '#db/repositories/obfuscatorPreset/resolve';

const PUBLIC_CLIENT_SHAPE = {
  with: {
    installLink: true,
    preset: {
      columns: { id: true, name: true, isDefault: true, mode: true },
    },
  },
  columns: {
    privateKey: false,
    preSharedKey: false,
  },
} as const;

const nameFilter = or(
  like(client.name, sql.placeholder('filter')),
  like(client.ipv4Address, sql.placeholder('filter')),
  like(client.ipv6Address, sql.placeholder('filter'))
);

function createPreparedStatement(db: DBType) {
  return {
    findAll: db.query.client
      .findMany({ with: { installLink: true } })
      .prepare(),
    findAllPublic: db.query.client.findMany(PUBLIC_CLIENT_SHAPE).prepare(),
    findAllPublicFiltered: db.query.client
      .findMany({ ...PUBLIC_CLIENT_SHAPE, where: nameFilter })
      .prepare(),
    findByUserId: db.query.client
      .findMany({
        ...PUBLIC_CLIENT_SHAPE,
        where: eq(client.userId, sql.placeholder('userId')),
      })
      .prepare(),
    findByUserIdFiltered: db.query.client
      .findMany({
        ...PUBLIC_CLIENT_SHAPE,
        where: and(eq(client.userId, sql.placeholder('userId')), nameFilter),
      })
      .prepare(),
    findById: db.query.client
      .findFirst({ where: eq(client.id, sql.placeholder('id')) })
      .prepare(),
    toggle: db
      .update(client)
      .set({ enabled: sql.placeholder('enabled') as never as boolean })
      .where(eq(client.id, sql.placeholder('id')))
      .prepare(),
    delete: db
      .delete(client)
      .where(eq(client.id, sql.placeholder('id')))
      .prepare(),
  };
}

function withDates<T extends { createdAt: string; updatedAt: string }>(
  rows: T[]
) {
  return rows.map((row) => ({
    ...row,
    createdAt: new Date(row.createdAt),
    updatedAt: new Date(row.updatedAt),
  }));
}

function filterPattern(filter: string) {
  return `%${filter}%`;
}

async function assertNameUnique(
  executor: DBExecutor,
  name: string,
  excludeId?: ID
) {
  const normalized = normalizeClientName(name);
  const rows = await executor.query.client
    .findMany({ columns: { id: true, name: true } })
    .execute();
  const duplicate = rows.find(
    (c) => c.id !== excludeId && normalizeClientName(c.name) === normalized
  );
  if (duplicate) {
    throw createError({
      statusCode: 409,
      statusMessage: `A client named "${duplicate.name}" already exists. Client names must be unique (case-insensitive).`,
    });
  }
}

async function requirePreset(
  executor: DBExecutor,
  presetId: number | null | undefined
) {
  const preset = await resolvePreset(executor, presetId ?? null);
  if (presetId != null && preset?.id !== presetId) {
    throw createError({
      statusCode: 400,
      statusMessage: `Obfuscator preset ${presetId} not found`,
    });
  }
  return preset;
}

async function loadInterface(executor: DBExecutor) {
  const iface = await executor.query.wgInterface
    .findFirst({ where: eq(wgInterface.name, WG_INTERFACE_NAME) })
    .execute();
  if (!iface) {
    throw new Error('WireGuard interface not found');
  }
  return iface;
}

export class ClientService extends Repository<
  ReturnType<typeof createPreparedStatement>
> {
  constructor(db: DBType) {
    super(db, createPreparedStatement);
  }

  getAll() {
    return this.statements.findAll.execute();
  }

  async getAllPublic() {
    return withDates(await this.statements.findAllPublic.execute());
  }

  async getAllPublicFiltered(filter: string) {
    return withDates(
      await this.statements.findAllPublicFiltered.execute({
        filter: filterPattern(filter),
      })
    );
  }

  async getForUser(userId: ID) {
    return withDates(await this.statements.findByUserId.execute({ userId }));
  }

  async getForUserFiltered(userId: ID, filter: string) {
    return withDates(
      await this.statements.findByUserIdFiltered.execute({
        userId,
        filter: filterPattern(filter),
      })
    );
  }

  get(id: ID) {
    return this.statements.findById.execute({ id });
  }

  async getSocks5PresetMembers() {
    const [defaultPreset, rows] = await Promise.all([
      resolvePreset(this.db, null),
      this.db.query.client
        .findMany({
          where: and(isNotNull(client.socks5Login), eq(client.enabled, true)),
          columns: {
            presetId: true,
            socks5Login: true,
            socks5Password: true,
          },
        })
        .execute(),
    ]);

    return rows.flatMap((r) => {
      const presetId = r.presetId ?? defaultPreset?.id;
      if (presetId === undefined || !r.socks5Login || !r.socks5Password) {
        return [];
      }
      return [
        {
          presetId,
          socks5Login: r.socks5Login,
          socks5Password: r.socks5Password,
        },
      ];
    });
  }

  async create(userId: ID, { name, expiresAt, presetId }: ClientCreateType) {
    const privateKey = await wg.generatePrivateKey();
    const publicKey = await wg.getPublicKey(privateKey);
    const preSharedKey = await wg.generatePreSharedKey();

    return this.db.transaction(async (tx) => {
      await assertNameUnique(tx, name);
      const iface = await loadInterface(tx);

      const config = await tx.query.userConfig
        .findFirst({ where: eq(userConfig.id, iface.name) })
        .execute();
      if (!config) {
        throw new Error('WireGuard interface configuration not found');
      }

      const addresses = await tx.query.client
        .findMany({ columns: { ipv4Address: true, ipv6Address: true } })
        .execute();
      const ipv4Address = nextIP(
        4,
        parseCidr(iface.ipv4Cidr),
        new Set(addresses.map((a) => a.ipv4Address))
      );
      const ipv6Address = nextIP(
        6,
        parseCidr(iface.ipv6Cidr),
        new Set(addresses.map((a) => a.ipv6Address))
      );

      const preset = await requirePreset(tx, presetId);
      const isSocks5 = preset?.mode === 'SOCKS5';

      return tx
        .insert(client)
        .values({
          name,
          userId,
          interfaceId: iface.name,
          presetId: presetId ?? null,
          socks5Login: isSocks5 ? generateSocks5Credential() : null,
          socks5Password: isSocks5 ? generateSocks5Credential() : null,
          expiresAt,
          privateKey,
          publicKey,
          preSharedKey,
          ipv4Address,
          ipv6Address,
          mtu: config.defaultMtu,
          persistentKeepalive: config.defaultPersistentKeepalive,
          serverAllowedIps: [],
          enabled: true,
        })
        .returning({ clientId: client.id })
        .execute();
    });
  }

  toggle(id: ID, enabled: boolean) {
    return this.statements.toggle.execute({ id, enabled });
  }

  async ensureSocks5Credentials(
    id: ID
  ): Promise<{ login: string; password: string }> {
    const current = await this.get(id);
    if (current?.socks5Login && current.socks5Password) {
      return { login: current.socks5Login, password: current.socks5Password };
    }
    const login = generateSocks5Credential();
    const password = generateSocks5Credential();
    await this.db
      .update(client)
      .set({ socks5Login: login, socks5Password: password })
      .where(eq(client.id, id))
      .execute();
    return { login, password };
  }

  delete(id: ID) {
    return this.statements.delete.execute({ id });
  }

  update(id: ID, data: UpdateClientType) {
    return this.db.transaction(async (tx) => {
      await assertNameUnique(tx, data.name, id);
      const iface = await loadInterface(tx);

      if (!containsCidr(iface.ipv4Cidr, data.ipv4Address)) {
        throw createError({
          statusCode: 400,
          statusMessage: `IPv4 address ${data.ipv4Address} is not within the interface subnet ${iface.ipv4Cidr}. Widen the WireGuard IPv4 subnet under Admin → Network Interface to use this range.`,
        });
      }

      if (!containsCidr(iface.ipv6Cidr, data.ipv6Address)) {
        throw createError({
          statusCode: 400,
          statusMessage: `IPv6 address ${data.ipv6Address} is not within the interface subnet ${iface.ipv6Cidr}. Widen the WireGuard IPv6 subnet under Admin → Network Interface to use this range.`,
        });
      }

      const values: Partial<ClientType> = { ...data };
      const preset = await requirePreset(tx, data.presetId);
      if (preset?.mode === 'SOCKS5') {
        const current = await tx.query.client
          .findFirst({
            where: eq(client.id, id),
            columns: { socks5Login: true, socks5Password: true },
          })
          .execute();
        if (!current?.socks5Login || !current.socks5Password) {
          values.socks5Login = generateSocks5Credential();
          values.socks5Password = generateSocks5Credential();
        }
      } else {
        values.socks5Login = null;
        values.socks5Password = null;
      }

      await tx.update(client).set(values).where(eq(client.id, id)).execute();
    });
  }
}
