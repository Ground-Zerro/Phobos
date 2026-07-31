export const MEDIA_OBFUSCATE_BYTES = 16;

export const WIREGUARD_BIND_ANY = '0.0.0.0';

export type ObfuscationMasking = 'STUN' | 'MEDIA' | 'AUTO' | 'NONE' | 'TLS';

export type ObfuscationMode = 'WIREGUARD' | 'SOCKS5';

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
