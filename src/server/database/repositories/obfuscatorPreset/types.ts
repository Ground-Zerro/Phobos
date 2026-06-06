import type { InferSelectModel } from 'drizzle-orm';
import z from 'zod';

import type { obfuscatorPreset } from './schema';

export type ObfuscatorPresetType = InferSelectModel<typeof obfuscatorPreset>;

export const OBFUSCATOR_PORT_MIN = 51822;
export const OBFUSCATOR_PORT_MAX = 51921;

const name = z
  .string({ message: t('zod.obfuscatorPreset.name') })
  .min(1, t('zod.obfuscatorPreset.name'))
  .max(64, t('zod.obfuscatorPreset.name'))
  .pipe(safeStringRefine);

const extPort = z
  .number({ message: t('zod.obfuscatorPreset.extPort') })
  .int()
  .min(OBFUSCATOR_PORT_MIN, { message: t('zod.obfuscatorPreset.extPort') })
  .max(OBFUSCATOR_PORT_MAX, { message: t('zod.obfuscatorPreset.extPort') });

const key = z
  .string({ message: t('zod.obfuscatorPreset.key') })
  .min(3)
  .max(255)
  .pipe(safeStringRefine);

const masking = z.enum(['STUN', 'MEDIA', 'AUTO', 'NONE'], {
  message: t('zod.obfuscatorPreset.masking'),
});

const idle = z
  .number({ message: t('zod.obfuscatorPreset.idle') })
  .int()
  .min(30)
  .max(3600);

const dummy = z
  .number({ message: t('zod.obfuscatorPreset.dummy') })
  .int()
  .min(0)
  .max(255);

const clientWgLocalPort = z
  .number({ message: t('zod.obfuscatorPreset.clientWgLocalPort') })
  .int()
  .min(1)
  .max(65535);

export const ObfuscatorPresetCreateSchema = z.object({
  name,
  extPort: extPort.optional(),
  key: key.optional(),
  masking: masking.optional(),
  idle: idle.optional(),
  dummy: dummy.optional(),
  clientWgLocalPort: clientWgLocalPort.optional(),
});

export type ObfuscatorPresetCreateType = z.infer<
  typeof ObfuscatorPresetCreateSchema
>;

export const ObfuscatorPresetUpdateSchema = z.object({
  name,
  extPort,
  key,
  masking,
  idle,
  dummy,
  clientWgLocalPort,
});

export type ObfuscatorPresetUpdateType = z.infer<
  typeof ObfuscatorPresetUpdateSchema
>;

const presetId = z.coerce.number({ message: t('zod.obfuscatorPreset.id') });

export const ObfuscatorPresetGetSchema = z.object({
  presetId,
});
