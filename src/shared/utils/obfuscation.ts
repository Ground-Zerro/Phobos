export const OBFUSCATION_MODES = ['WIREGUARD', 'SOCKS5'] as const;

export const OBFUSCATION_MASKINGS = [
  'STUN',
  'MEDIA',
  'AUTO',
  'NONE',
  'TLS',
] as const;

export const OBFUSCATOR_VERBOSITY = [
  'error',
  'warn',
  'info',
  'debug',
  'trace',
] as const;

export type ObfuscationMode = (typeof OBFUSCATION_MODES)[number];

export type ObfuscationMasking = (typeof OBFUSCATION_MASKINGS)[number];

export type ObfuscatorVerbosity = (typeof OBFUSCATOR_VERBOSITY)[number];

export const PRESET_DEFAULTS = {
  masking: 'STUN',
  obfuscateBytes: 0,
  dummy: 40,
  verbose: 'error',
  clientWgLocalPort: 13255,
  clientLocalPort: 1080,
} as const satisfies {
  masking: ObfuscationMasking;
  obfuscateBytes: number;
  dummy: number;
  verbose: ObfuscatorVerbosity;
  clientWgLocalPort: number;
  clientLocalPort: number;
};

export const MEDIA_OBFUSCATE_BYTES = 16;

export const WIREGUARD_BIND_ANY = '0.0.0.0';

const MODE_ONLY_MASKINGS: Partial<Record<ObfuscationMasking, ObfuscationMode>> =
  {
    AUTO: 'WIREGUARD',
    TLS: 'SOCKS5',
  };

export function isMaskingAllowed(
  mode: ObfuscationMode,
  masking: ObfuscationMasking
): boolean {
  const only = MODE_ONLY_MASKINGS[masking];
  return only === undefined || only === mode;
}

export function effectiveSourceIf(preset: {
  mode: ObfuscationMode;
  sourceIf: string;
}): string {
  if (preset.sourceIf) return preset.sourceIf;
  return preset.mode === 'SOCKS5' ? '' : WIREGUARD_BIND_ANY;
}

export function effectiveObfuscateBytes(preset: {
  masking: ObfuscationMasking;
  obfuscateBytes: number;
}): number {
  return preset.masking === 'MEDIA' && preset.obfuscateBytes === 0
    ? MEDIA_OBFUSCATE_BYTES
    : preset.obfuscateBytes;
}
