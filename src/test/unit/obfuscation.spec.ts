import { describe, expect, test } from 'vitest';
import {
  effectiveObfuscateBytes,
  effectiveSourceIf,
  MEDIA_OBFUSCATE_BYTES,
  WIREGUARD_BIND_ANY,
} from '../../shared/utils/obfuscation';

describe('effectiveObfuscateBytes', () => {
  test('MEDIA resolves zero to the partial-XOR default', () => {
    expect(
      effectiveObfuscateBytes({ masking: 'MEDIA', obfuscateBytes: 0 })
    ).toBe(MEDIA_OBFUSCATE_BYTES);
  });

  test('explicit values are kept as configured', () => {
    expect(
      effectiveObfuscateBytes({ masking: 'MEDIA', obfuscateBytes: 4 })
    ).toBe(4);
    expect(
      effectiveObfuscateBytes({ masking: 'STUN', obfuscateBytes: 8 })
    ).toBe(8);
  });

  test('other masking modes keep full-packet obfuscation', () => {
    for (const masking of ['STUN', 'AUTO', 'NONE', 'TLS'] as const) {
      expect(effectiveObfuscateBytes({ masking, obfuscateBytes: 0 })).toBe(0);
    }
  });
});

describe('effectiveSourceIf', () => {
  test('AUTO lets the SOCKS5 engine pick its dual-stack default', () => {
    expect(effectiveSourceIf({ mode: 'SOCKS5', sourceIf: '' })).toBe('');
  });

  test('AUTO binds WireGuard presets to IPv4, the only family it supports', () => {
    expect(effectiveSourceIf({ mode: 'WIREGUARD', sourceIf: '' })).toBe(
      WIREGUARD_BIND_ANY
    );
  });

  test('an explicit address wins in both modes', () => {
    expect(effectiveSourceIf({ mode: 'SOCKS5', sourceIf: '::' })).toBe('::');
    expect(effectiveSourceIf({ mode: 'SOCKS5', sourceIf: '10.0.0.5' })).toBe(
      '10.0.0.5'
    );
    expect(effectiveSourceIf({ mode: 'WIREGUARD', sourceIf: '10.0.0.5' })).toBe(
      '10.0.0.5'
    );
  });
});
