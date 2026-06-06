import { and, eq, ne, sql } from 'drizzle-orm';
import { obfuscatorPreset } from './schema';
import {
  OBFUSCATOR_PORT_MAX,
  OBFUSCATOR_PORT_MIN,
  type ObfuscatorPresetCreateType,
  type ObfuscatorPresetType,
  type ObfuscatorPresetUpdateType,
} from './types';
import { client as clientSchema } from '#db/schema';
import type { DBType } from '#db/sqlite';

export class ObfuscatorPresetService {
  #db: DBType;

  constructor(db: DBType) {
    this.#db = db;
  }

  list() {
    return this.#db.query.obfuscatorPreset
      .findMany({ orderBy: (p, { desc, asc }) => [desc(p.isDefault), asc(p.id)] })
      .execute();
  }

  async get(id: number): Promise<ObfuscatorPresetType> {
    const row = await this.#db.query.obfuscatorPreset
      .findFirst({ where: eq(obfuscatorPreset.id, id) })
      .execute();
    if (!row) {
      throw new Error(`Obfuscator preset ${id} not found`);
    }
    return row;
  }

  async getDefault(): Promise<ObfuscatorPresetType> {
    const row = await this.#db.query.obfuscatorPreset
      .findFirst({ where: eq(obfuscatorPreset.isDefault, true) })
      .execute();
    if (!row) {
      throw new Error('No default obfuscator preset configured');
    }
    return row;
  }

  async getForClient(
    presetId: number | null | undefined
  ): Promise<ObfuscatorPresetType> {
    if (presetId == null) return this.getDefault();
    try {
      return await this.get(presetId);
    } catch {
      return this.getDefault();
    }
  }

  async usedPorts(excludeId?: number): Promise<Set<number>> {
    const rows = await this.#db.query.obfuscatorPreset
      .findMany({ columns: { id: true, extPort: true } })
      .execute();
    return new Set(
      rows.filter((r) => r.id !== excludeId).map((r) => r.extPort)
    );
  }

  async pickFreePort(excludeId?: number): Promise<number> {
    const used = await this.usedPorts(excludeId);
    for (let p = OBFUSCATOR_PORT_MIN; p <= OBFUSCATOR_PORT_MAX; p++) {
      if (!used.has(p)) return p;
    }
    throw new Error(
      `No free obfuscator port in range ${OBFUSCATOR_PORT_MIN}-${OBFUSCATOR_PORT_MAX}`
    );
  }

  async clientCounts(): Promise<Record<number, number>> {
    const rows = await this.#db
      .select({
        presetId: clientSchema.presetId,
        count: sql<number>`count(*)`,
      })
      .from(clientSchema)
      .groupBy(clientSchema.presetId)
      .execute();

    const result: Record<number, number> = {};
    for (const r of rows) {
      if (r.presetId != null) result[r.presetId] = Number(r.count);
    }
    return result;
  }

  async create(data: ObfuscatorPresetCreateType): Promise<ObfuscatorPresetType> {
    const extPort = data.extPort ?? (await this.pickFreePort());
    if (extPort < OBFUSCATOR_PORT_MIN || extPort > OBFUSCATOR_PORT_MAX) {
      throw new Error(
        `Port ${extPort} is outside allowed range ${OBFUSCATOR_PORT_MIN}-${OBFUSCATOR_PORT_MAX}`
      );
    }
    const inserted = await this.#db
      .insert(obfuscatorPreset)
      .values({
        name: data.name,
        isDefault: false,
        extPort,
        key: data.key ?? generateObfuscatorKey(),
        masking: data.masking ?? 'STUN',
        idle: data.idle ?? 300,
        dummy: data.dummy ?? 40,
        clientWgLocalPort: data.clientWgLocalPort ?? 13255,
      })
      .returning()
      .execute();
    if (!inserted[0]) {
      throw new Error('Failed to insert obfuscator preset');
    }
    return inserted[0];
  }

  async update(
    id: number,
    data: Partial<ObfuscatorPresetUpdateType>
  ): Promise<ObfuscatorPresetType> {
    if (data.extPort != null) {
      if (
        data.extPort < OBFUSCATOR_PORT_MIN ||
        data.extPort > OBFUSCATOR_PORT_MAX
      ) {
        throw new Error(
          `Port ${data.extPort} is outside allowed range ${OBFUSCATOR_PORT_MIN}-${OBFUSCATOR_PORT_MAX}`
        );
      }
    }
    const updated = await this.#db
      .update(obfuscatorPreset)
      .set(data)
      .where(eq(obfuscatorPreset.id, id))
      .returning()
      .execute();
    if (!updated[0]) {
      throw new Error(`Obfuscator preset ${id} not found`);
    }
    return updated[0];
  }

  async setDefault(id: number): Promise<void> {
    await this.#db.transaction(async (tx) => {
      const target = await tx.query.obfuscatorPreset
        .findFirst({ where: eq(obfuscatorPreset.id, id) })
        .execute();
      if (!target) {
        throw new Error(`Obfuscator preset ${id} not found`);
      }

      await tx
        .update(obfuscatorPreset)
        .set({ isDefault: false })
        .where(and(eq(obfuscatorPreset.isDefault, true), ne(obfuscatorPreset.id, id)))
        .execute();

      await tx
        .update(obfuscatorPreset)
        .set({ isDefault: true })
        .where(eq(obfuscatorPreset.id, id))
        .execute();
    });
  }

  async delete(id: number): Promise<void> {
    const row = await this.get(id);
    if (row.isDefault) {
      throw new Error('Cannot delete the default obfuscator preset');
    }
    await this.#db
      .delete(obfuscatorPreset)
      .where(eq(obfuscatorPreset.id, id))
      .execute();
  }

  async regenerateKey(id: number): Promise<ObfuscatorPresetType> {
    return this.update(id, { key: generateObfuscatorKey() });
  }

  async regeneratePort(id: number): Promise<ObfuscatorPresetType> {
    const port = await this.pickFreePort(id);
    return this.update(id, { extPort: port });
  }

  async ensureDefault(seed: {
    extPort: number;
    key: string;
    masking: 'STUN' | 'MEDIA' | 'AUTO' | 'NONE';
    idle: number;
    dummy: number;
    clientWgLocalPort: number;
  }): Promise<void> {
    const existing = await this.#db.query.obfuscatorPreset
      .findFirst({ where: eq(obfuscatorPreset.isDefault, true) })
      .execute();
    if (existing) return;

    await this.#db
      .insert(obfuscatorPreset)
      .values({
        name: 'default',
        isDefault: true,
        extPort: seed.extPort,
        key: seed.key,
        masking: seed.masking,
        idle: seed.idle,
        dummy: seed.dummy,
        clientWgLocalPort: seed.clientWgLocalPort,
      })
      .execute();
  }
}
