import { beforeAll, describe, expect, test, vi } from 'vitest';
import * as serverTypes from '../../server/utils/types';

let InterfaceUpdateSchema: typeof import('../../server/database/repositories/interface/types').InterfaceUpdateSchema;

beforeAll(async () => {
  for (const [name, value] of Object.entries(serverTypes)) {
    vi.stubGlobal(name, value);
  }
  ({ InterfaceUpdateSchema } =
    await import('../../server/database/repositories/interface/types'));
});

describe('InterfaceUpdateSchema', () => {
  test('drops subnet fields so a stale form cannot overwrite the CIDR', () => {
    const parsed = InterfaceUpdateSchema.parse({
      ipv4Cidr: '10.8.0.0/24',
      ipv6Cidr: 'fdcc:ad94:bacf:61a4::cafe:0/112',
      mtu: 1420,
      device: 'eth0',
      enabled: true,
      firewallEnabled: false,
      egressMode: 'wan',
      serverPublicIpV4: '109.172.81.3',
      serverPublicIpV6: null,
      serverPublicDomain: null,
    });
    expect(parsed).not.toHaveProperty('ipv4Cidr');
    expect(parsed).not.toHaveProperty('ipv6Cidr');
    expect(parsed.mtu).toBe(1420);
  });
});
