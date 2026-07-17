import { eq, sql, or, like, and, isNotNull } from 'drizzle-orm';
import { containsCidr, parseCidr } from 'cidr-tools';
import { client } from './schema';
import type {
  ClientCreateFromExistingType,
  ClientCreateType,
  ClientType,
  UpdateClientType,
} from './types';
import type { DBType } from '#db/sqlite';
import { wgInterface, userConfig, obfuscatorPreset } from '#db/schema';

function createPreparedStatement(db: DBType) {
  return {
    findAll: db.query.client
      .findMany({
        with: {
          installLink: true,
        },
      })
      .prepare(),
    findAllPublic: db.query.client
      .findMany({
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
      })
      .prepare(),
    findById: db.query.client
      .findFirst({ where: eq(client.id, sql.placeholder('id')) })
      .prepare(),
    findByUserId: db.query.client
      .findMany({
        where: eq(client.userId, sql.placeholder('userId')),
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
      })
      .prepare(),
    findAllPublicFiltered: db.query.client
      .findMany({
        where: or(
          like(client.name, sql.placeholder('filter')),
          like(client.ipv4Address, sql.placeholder('filter')),
          like(client.ipv6Address, sql.placeholder('filter'))
        ),
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
      })
      .prepare(),
    findByUserIdFiltered: db.query.client
      .findMany({
        where: and(
          eq(client.userId, sql.placeholder('userId')),
          or(
            like(client.name, sql.placeholder('filter')),
            like(client.ipv4Address, sql.placeholder('filter')),
            like(client.ipv6Address, sql.placeholder('filter'))
          )
        ),
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
      })
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

export class ClientService {
  #db: DBType;
  #statements: ReturnType<typeof createPreparedStatement>;

  constructor(db: DBType) {
    this.#db = db;
    this.#statements = createPreparedStatement(db);
  }

  async getForUser(userId: ID) {
    const result = await this.#statements.findByUserId.execute({ userId });
    return result.map((row) => ({
      ...row,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
    }));
  }

  /**
   * Never return values directly from this function. Use {@link getAllPublic} instead.
   */
  async getAll() {
    const result = await this.#statements.findAll.execute();
    return result.map((row) => ({
      ...row,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
    }));
  }

  /**
   * Returns all clients without sensitive data
   */
  async getAllPublic() {
    const result = await this.#statements.findAllPublic.execute();
    return result.map((row) => ({
      ...row,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
    }));
  }

  /**
   * Get clients based on user ID and filter conditions
   */
  async getForUserFiltered(userId: ID, filter: string) {
    const filterPattern = `%${filter.toLowerCase()}%`;

    const result = await this.#statements.findByUserIdFiltered.execute({
      userId,
      filter: filterPattern,
    });

    return result.map((row) => ({
      ...row,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
    }));
  }

  /**
   * Get all clients based on filter conditions without sensitive data
   */
  async getAllPublicFiltered(filter: string) {
    const filterPattern = `%${filter.toLowerCase()}%`;

    const result = await this.#statements.findAllPublicFiltered.execute({
      filter: filterPattern,
    });

    return result.map((row) => ({
      ...row,
      createdAt: new Date(row.createdAt),
      updatedAt: new Date(row.updatedAt),
    }));
  }

  get(id: ID) {
    return this.#statements.findById.execute({ id });
  }

  /**
   * Lightweight lookup of every client with SOCKS5 credentials (i.e. whose
   * preset was in SOCKS5 mode when credentials were generated), used to
   * build the RFC1929 user list for the corresponding server process.
   */
  async getSocks5PresetMembers(): Promise<
    {
      id: number;
      presetId: number;
      socks5Login: string;
      socks5Password: string;
    }[]
  > {
    const defaultPreset = await this.#db.query.obfuscatorPreset
      .findFirst({
        where: eq(obfuscatorPreset.isDefault, true),
        columns: { id: true },
      })
      .execute();

    const rows = await this.#db.query.client
      .findMany({
        where: and(isNotNull(client.socks5Login), eq(client.enabled, true)),
        columns: {
          id: true,
          presetId: true,
          socks5Login: true,
          socks5Password: true,
        },
      })
      .execute();

    return rows.flatMap((r) => {
      const presetId = r.presetId ?? defaultPreset?.id ?? null;
      if (
        presetId == null ||
        r.socks5Login == null ||
        r.socks5Password == null
      ) {
        return [];
      }
      return [
        {
          id: r.id,
          presetId,
          socks5Login: r.socks5Login,
          socks5Password: r.socks5Password,
        },
      ];
    });
  }

  async create({ name, expiresAt, presetId }: ClientCreateType) {
    const privateKey = await wg.generatePrivateKey();
    const publicKey = await wg.getPublicKey(privateKey);
    const preSharedKey = await wg.generatePreSharedKey();

    return this.#db.transaction(async (tx) => {
      const clients = await tx.query.client.findMany().execute();

      const normalized = normalizeClientName(name);
      const duplicate = clients.find(
        (c) => normalizeClientName(c.name) === normalized
      );
      if (duplicate) {
        throw createError({
          statusCode: 409,
          statusMessage: `A client named "${duplicate.name}" already exists. Client names must be unique (case-insensitive).`,
        });
      }

      const clientInterface = await tx.query.wgInterface
        .findFirst({
          where: eq(wgInterface.name, 'wg0'),
        })
        .execute();

      if (!clientInterface) {
        throw new Error('WireGuard interface not found');
      }

      const clientConfig = await tx.query.userConfig
        .findFirst({
          where: eq(userConfig.id, clientInterface.name),
        })
        .execute();

      if (!clientConfig) {
        throw new Error('WireGuard interface configuration not found');
      }

      const ipv4Cidr = parseCidr(clientInterface.ipv4Cidr);
      const ipv4Address = nextIP(4, ipv4Cidr, clients);
      const ipv6Cidr = parseCidr(clientInterface.ipv6Cidr);
      const ipv6Address = nextIP(6, ipv6Cidr, clients);

      const preset =
        presetId != null
          ? await tx.query.obfuscatorPreset
              .findFirst({ where: eq(obfuscatorPreset.id, presetId) })
              .execute()
          : await tx.query.obfuscatorPreset
              .findFirst({ where: eq(obfuscatorPreset.isDefault, true) })
              .execute();
      const socks5Login =
        preset?.mode === 'SOCKS5' ? generateSocks5Credential() : null;
      const socks5Password =
        preset?.mode === 'SOCKS5' ? generateSocks5Credential() : null;

      return await tx
        .insert(client)
        .values({
          name,
          // TODO: properly assign user id
          userId: 1,
          interfaceId: 'wg0',
          presetId: presetId ?? null,
          socks5Login,
          socks5Password,
          expiresAt,
          privateKey,
          publicKey,
          preSharedKey,
          ipv4Address,
          ipv6Address,
          mtu: clientConfig.defaultMtu,
          persistentKeepalive: clientConfig.defaultPersistentKeepalive,
          serverAllowedIps: [],
          enabled: true,
        })
        .returning({ clientId: client.id })
        .execute();
    });
  }

  toggle(id: ID, enabled: boolean) {
    return this.#statements.toggle.execute({ id, enabled });
  }

  async setSocks5Credentials(id: ID, login: string, password: string) {
    await this.#db
      .update(client)
      .set({ socks5Login: login, socks5Password: password })
      .where(eq(client.id, id))
      .execute();
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
    await this.setSocks5Credentials(id, login, password);
    return { login, password };
  }

  delete(id: ID) {
    return this.#statements.delete.execute({ id });
  }

  update(id: ID, data: UpdateClientType) {
    return this.#db.transaction(async (tx) => {
      const clients = await tx.query.client.findMany().execute();
      const normalized = normalizeClientName(data.name);
      const duplicate = clients.find(
        (c) => c.id !== id && normalizeClientName(c.name) === normalized
      );
      if (duplicate) {
        throw createError({
          statusCode: 409,
          statusMessage: `A client named "${duplicate.name}" already exists. Client names must be unique (case-insensitive).`,
        });
      }

      const clientInterface = await tx.query.wgInterface
        .findFirst({
          where: eq(wgInterface.name, 'wg0'),
        })
        .execute();

      if (!clientInterface) {
        throw new Error('WireGuard interface not found');
      }

      if (!containsCidr(clientInterface.ipv4Cidr, data.ipv4Address)) {
        throw createError({
          statusCode: 400,
          statusMessage: `IPv4 address ${data.ipv4Address} is not within the interface subnet ${clientInterface.ipv4Cidr}. Widen the WireGuard IPv4 subnet under Admin → Network Interface to use this range.`,
        });
      }

      if (!containsCidr(clientInterface.ipv6Cidr, data.ipv6Address)) {
        throw createError({
          statusCode: 400,
          statusMessage: `IPv6 address ${data.ipv6Address} is not within the interface subnet ${clientInterface.ipv6Cidr}. Widen the WireGuard IPv6 subnet under Admin → Network Interface to use this range.`,
        });
      }

      const values: Partial<ClientType> = { ...data };
      // A null presetId falls back to the server's default preset, whose
      // mode is whatever the admin has configured it to be.
      const presetMode =
        data.presetId != null
          ? (
              await tx.query.obfuscatorPreset
                .findFirst({ where: eq(obfuscatorPreset.id, data.presetId) })
                .execute()
            )?.mode
          : (
              await tx.query.obfuscatorPreset
                .findFirst({ where: eq(obfuscatorPreset.isDefault, true) })
                .execute()
            )?.mode;
      if (presetMode === 'SOCKS5') {
        const current = await tx.query.client
          .findFirst({
            where: eq(client.id, id),
            columns: { socks5Login: true, socks5Password: true },
          })
          .execute();
        if (!current?.socks5Login || !current?.socks5Password) {
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

  async createFromExisting({
    name,
    enabled,
    ipv4Address,
    ipv6Address,
    preSharedKey,
    privateKey,
    publicKey,
  }: ClientCreateFromExistingType) {
    const clientConfig = await Database.userConfigs.get();

    return this.#db
      .insert(client)
      .values({
        name,
        userId: 1,
        interfaceId: 'wg0',
        presetId: null,
        privateKey,
        publicKey,
        preSharedKey,
        ipv4Address,
        ipv6Address,
        mtu: clientConfig.defaultMtu,
        allowedIps: clientConfig.defaultAllowedIps,
        dns: clientConfig.defaultDns,
        persistentKeepalive: clientConfig.defaultPersistentKeepalive,
        serverAllowedIps: [],
        enabled,
      })
      .execute();
  }
}
