import { and, eq, ne, sql } from 'drizzle-orm';
import { obfuscatorPreset } from './schema';
import {
  isPortInModeRange,
  obfuscatorPortRange,
  type ObfuscatorPresetCreateType,
  type ObfuscatorPresetType,
  type ObfuscatorPresetUpdateType,
} from './types';
import { resolvePreset } from './resolve';
import { client as clientSchema } from '#db/schema';
import { Repository } from '#db/repository';
import type { DBType } from '#db/sqlite';
import {
  PRESET_DEFAULTS,
  type ObfuscationMode,
} from '#shared/utils/obfuscation';

type ObfuscatorPresetInsert = typeof obfuscatorPreset.$inferInsert;

type DefaultPresetSeed = Omit<
  ObfuscatorPresetInsert,
  'id' | 'name' | 'isDefault' | 'mode' | 'createdAt' | 'updatedAt'
>;

function createPreparedStatement(db: DBType) {
  return {
    list: db.query.obfuscatorPreset
      .findMany({
        orderBy: (p, { desc, asc }) => [desc(p.isDefault), asc(p.id)],
      })
      .prepare(),
    findById: db.query.obfuscatorPreset
      .findFirst({ where: eq(obfuscatorPreset.id, sql.placeholder('id')) })
      .prepare(),
    findDefault: db.query.obfuscatorPreset
      .findFirst({ where: eq(obfuscatorPreset.isDefault, true) })
      .prepare(),
  };
}

export class ObfuscatorPresetService extends Repository<
  ReturnType<typeof createPreparedStatement>
> {
  constructor(db: DBType) {
    super(db, createPreparedStatement);
  }

  list() {
    return this.statements.list.execute();
  }

  async get(id: number): Promise<ObfuscatorPresetType> {
    const row = await this.statements.findById.execute({ id });
    if (!row) {
      throw new Error(`Obfuscator preset ${id} not found`);
    }
    return row;
  }

  async getDefault(): Promise<ObfuscatorPresetType> {
    const row = await this.statements.findDefault.execute();
    if (!row) {
      throw new Error('No default obfuscator preset configured');
    }
    return row;
  }

  async getForClient(presetId: number | null): Promise<ObfuscatorPresetType> {
    const preset = await resolvePreset(this.db, presetId);
    if (!preset) {
      throw new Error('No default obfuscator preset configured');
    }
    return preset;
  }

  async #usedPorts(excludeId?: number): Promise<Set<number>> {
    const rows = await this.db.query.obfuscatorPreset
      .findMany({ columns: { id: true, extPort: true } })
      .execute();
    return new Set(
      rows.filter((r) => r.id !== excludeId).map((r) => r.extPort)
    );
  }

  async pickFreePort(
    mode: ObfuscationMode,
    excludeId?: number
  ): Promise<number> {
    const used = await this.#usedPorts(excludeId);
    const { min, max } = obfuscatorPortRange(mode);
    for (let p = min; p <= max; p++) {
      if (!used.has(p)) return p;
    }
    throw new Error(`No free obfuscator port in range ${min}-${max}`);
  }

  #assertPortInRange(extPort: number, mode: ObfuscationMode): void {
    const { min, max } = obfuscatorPortRange(mode);
    if (extPort < min || extPort > max) {
      throw new Error(
        `Port ${extPort} is outside allowed ${mode} range ${min}-${max}`
      );
    }
  }

  async clientCounts(): Promise<Record<number, number>> {
    const [rows, defaultPreset] = await Promise.all([
      this.db
        .select({
          presetId: clientSchema.presetId,
          count: sql<number>`count(*)`,
        })
        .from(clientSchema)
        .groupBy(clientSchema.presetId)
        .execute(),
      this.getDefault(),
    ]);

    const result: Record<number, number> = {};
    for (const r of rows) {
      const presetId = r.presetId ?? defaultPreset.id;
      result[presetId] = (result[presetId] ?? 0) + Number(r.count);
    }
    return result;
  }

  async create(
    data: ObfuscatorPresetCreateType
  ): Promise<ObfuscatorPresetType> {
    const mode = data.mode ?? 'WIREGUARD';
    const extPort = data.extPort ?? (await this.pickFreePort(mode));
    this.#assertPortInRange(extPort, mode);
    const inserted = await this.db
      .insert(obfuscatorPreset)
      .values({
        ...PRESET_DEFAULTS,
        ...data,
        name: data.name,
        isDefault: false,
        mode,
        extPort,
        sourceIf: data.sourceIf ?? '',
        target: data.target?.trim() ? data.target.trim() : null,
        key: data.key ?? generateObfuscatorKey(),
        mediaSsrc: data.mediaSsrc ?? null,
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
    const values: Partial<ObfuscatorPresetType> = { ...data };
    if (data.extPort != null || data.mode != null) {
      const row = await this.get(id);
      const mode = data.mode ?? row.mode;
      const extPort = data.extPort ?? row.extPort;
      if (!isPortInModeRange(extPort, mode)) {
        if (data.extPort != null && data.extPort !== row.extPort) {
          this.#assertPortInRange(data.extPort, mode);
        }
        values.extPort = await this.pickFreePort(mode, id);
      }
    }
    if (data.target !== undefined) {
      values.target = data.target.trim() ? data.target.trim() : null;
    }
    const updated = await this.db
      .update(obfuscatorPreset)
      .set(values)
      .where(eq(obfuscatorPreset.id, id))
      .returning()
      .execute();
    if (!updated[0]) {
      throw new Error(`Obfuscator preset ${id} not found`);
    }
    return updated[0];
  }

  async setDefault(id: number): Promise<void> {
    await this.db.transaction(async (tx) => {
      const target = await tx.query.obfuscatorPreset
        .findFirst({ where: eq(obfuscatorPreset.id, id) })
        .execute();
      if (!target) {
        throw new Error(`Obfuscator preset ${id} not found`);
      }

      await tx
        .update(obfuscatorPreset)
        .set({ isDefault: false })
        .where(
          and(eq(obfuscatorPreset.isDefault, true), ne(obfuscatorPreset.id, id))
        )
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
    await this.db
      .delete(obfuscatorPreset)
      .where(eq(obfuscatorPreset.id, id))
      .execute();
  }

  regenerateKey(id: number): Promise<ObfuscatorPresetType> {
    return this.update(id, { key: generateObfuscatorKey() });
  }

  async regeneratePort(id: number): Promise<ObfuscatorPresetType> {
    const row = await this.get(id);
    const port = await this.pickFreePort(row.mode, id);
    return this.update(id, { extPort: port });
  }

  async ensureDefault(seed: DefaultPresetSeed): Promise<void> {
    if (await this.statements.findDefault.execute()) return;

    await this.db
      .insert(obfuscatorPreset)
      .values({ ...seed, name: 'default', isDefault: true, mode: 'WIREGUARD' })
      .execute();
  }
}
