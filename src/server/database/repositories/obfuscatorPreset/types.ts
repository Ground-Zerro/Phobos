import type { InferSelectModel } from 'drizzle-orm';
import z from 'zod';

import type { obfuscatorPreset } from './schema';
import {
  OBFUSCATION_MASKINGS,
  OBFUSCATION_MODES,
  OBFUSCATOR_VERBOSITY,
  isMaskingAllowed,
  type ObfuscationMode,
} from '#shared/utils/obfuscation';

export type ObfuscatorPresetType = InferSelectModel<typeof obfuscatorPreset>;

export const WIREGUARD_PORT_MIN = 51822;
const WIREGUARD_PORT_MAX = 51861;
const SOCKS5_PORT_MIN = 51862;
const SOCKS5_PORT_MAX = 51891;

export function obfuscatorPortRange(mode: ObfuscationMode) {
  return mode === 'SOCKS5'
    ? { min: SOCKS5_PORT_MIN, max: SOCKS5_PORT_MAX }
    : { min: WIREGUARD_PORT_MIN, max: WIREGUARD_PORT_MAX };
}

export function isPortInModeRange(
  port: number,
  mode: ObfuscationMode
): boolean {
  const { min, max } = obfuscatorPortRange(mode);
  return port >= min && port <= max;
}

const name = z
  .string({ message: t('zod.obfuscatorPreset.name') })
  .min(1, t('zod.obfuscatorPreset.name'))
  .max(64, t('zod.obfuscatorPreset.name'))
  .pipe(safeStringRefine);

const extPort = z
  .number({ message: t('zod.obfuscatorPreset.extPort') })
  .int()
  .min(WIREGUARD_PORT_MIN, { message: t('zod.obfuscatorPreset.extPort') })
  .max(SOCKS5_PORT_MAX, { message: t('zod.obfuscatorPreset.extPort') });

const sourceIf = z
  .string({ message: t('zod.obfuscatorPreset.sourceIf') })
  .max(255)
  .pipe(safeStringRefine);

const target = z
  .string({ message: t('zod.obfuscatorPreset.target') })
  .max(255)
  .refine((v) => v.length === 0 || /^\S+:\d{1,5}$/.test(v), {
    message: t('zod.obfuscatorPreset.target'),
  });

const key = z
  .string({ message: t('zod.obfuscatorPreset.key') })
  .min(3)
  .max(255)
  .pipe(safeStringRefine);

const mode = z.enum(OBFUSCATION_MODES, {
  message: t('zod.obfuscatorPreset.mode'),
});

const masking = z.enum(OBFUSCATION_MASKINGS, {
  message: t('zod.obfuscatorPreset.masking'),
});

const mediaSsrc = z
  .number({ message: t('zod.obfuscatorPreset.mediaSsrc') })
  .int()
  .min(0)
  .max(0xffffffff)
  .nullable();

const clientLocalPort = z
  .number({ message: t('zod.obfuscatorPreset.clientLocalPort') })
  .int()
  .min(1)
  .max(65535);

const obfuscateBytes = z
  .number({ message: t('zod.obfuscatorPreset.obfuscateBytes') })
  .int()
  .min(0)
  .max(1024);

const dummy = z
  .number({ message: t('zod.obfuscatorPreset.dummy') })
  .int()
  .min(0)
  .max(1024);

const verbose = z.enum(OBFUSCATOR_VERBOSITY, {
  message: t('zod.obfuscatorPreset.verbose'),
});

const clientWgLocalPort = z
  .number({ message: t('zod.obfuscatorPreset.clientWgLocalPort') })
  .int()
  .min(1)
  .max(65535);

export const ObfuscatorPresetCreateSchema = z
  .object({
    name,
    mode: mode.optional(),
    extPort: extPort.optional(),
    sourceIf: sourceIf.optional(),
    target: target.optional(),
    key: key.optional(),
    masking: masking.optional(),
    obfuscateBytes: obfuscateBytes.optional(),
    dummy: dummy.optional(),
    verbose: verbose.optional(),
    clientWgLocalPort: clientWgLocalPort.optional(),
    mediaSsrc: mediaSsrc.optional(),
    clientLocalPort: clientLocalPort.optional(),
  })
  .refine(
    (data) =>
      data.extPort == null ||
      isPortInModeRange(data.extPort, data.mode ?? 'WIREGUARD'),
    {
      message: t('zod.obfuscatorPreset.extPort'),
      path: ['extPort'],
    }
  );

export type ObfuscatorPresetCreateType = z.infer<
  typeof ObfuscatorPresetCreateSchema
>;

export const ObfuscatorPresetUpdateSchema = z
  .object({
    name,
    mode,
    extPort,
    sourceIf,
    target,
    key,
    masking,
    obfuscateBytes,
    dummy,
    verbose,
    clientWgLocalPort,
    mediaSsrc,
    clientLocalPort,
  })
  .refine(
    (data) =>
      !(
        data.masking === 'MEDIA' &&
        data.obfuscateBytes > 0 &&
        data.obfuscateBytes < 4
      ),
    {
      message: t('zod.obfuscatorPreset.obfuscateBytesMedia'),
      path: ['obfuscateBytes'],
    }
  )
  .superRefine((data, ctx) => {
    if (isMaskingAllowed(data.mode, data.masking)) return;
    ctx.addIssue({
      code: 'custom',
      path: ['masking'],
      message:
        data.mode === 'SOCKS5'
          ? t('zod.obfuscatorPreset.maskingAutoSocks5')
          : t('zod.obfuscatorPreset.maskingTlsWireguard'),
    });
  });

export type ObfuscatorPresetUpdateType = z.infer<
  typeof ObfuscatorPresetUpdateSchema
>;

const presetId = z.coerce.number({ message: t('zod.obfuscatorPreset.id') });

export const ObfuscatorPresetGetSchema = z.object({
  presetId,
});
