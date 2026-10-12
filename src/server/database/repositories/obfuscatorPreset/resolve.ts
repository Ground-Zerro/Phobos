import { eq } from 'drizzle-orm';
import type { DBExecutor } from '../../sqlite';
import { obfuscatorPreset } from './schema';

export async function resolvePreset(
  executor: DBExecutor,
  presetId: number | null
) {
  const assigned =
    presetId === null
      ? undefined
      : await executor.query.obfuscatorPreset
          .findFirst({ where: eq(obfuscatorPreset.id, presetId) })
          .execute();
  return (
    assigned ??
    executor.query.obfuscatorPreset
      .findFirst({ where: eq(obfuscatorPreset.isDefault, true) })
      .execute()
  );
}
