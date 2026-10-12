import { describe, expect, test } from 'vitest';
import { runtimeStatsTestExports } from '../../server/utils/RuntimeStats';
import { buildClientFullConfig } from '../../server/utils/clientConfig';

const { parseWgDump } = runtimeStatsTestExports;

describe('parseWgDump', () => {
  const dump = [
    'privkey\tpubkey\t51820\toff',
    'peerA=\tpsk\t127.0.0.1:40000\t10.8.0.2/32\t1700000000\t100\t200\toff',
    'peerB=\tpsk\t(none)\t10.8.0.3/32\t0\t0\t0\toff',
  ].join('\n');

  test('skips the interface line and keys peers by public key', () => {
    const peers = parseWgDump(dump);
    expect([...peers.keys()]).toEqual(['peerA=', 'peerB=']);
  });

  test('maps endpoint, handshake and transfer counters', () => {
    const peers = parseWgDump(dump);
    expect(peers.get('peerA=')).toEqual({
      endpoint: '127.0.0.1:40000',
      latestHandshakeAt: new Date(1700000000 * 1000),
      transferRx: 100,
      transferTx: 200,
    });
    expect(peers.get('peerB=')).toEqual({
      endpoint: null,
      latestHandshakeAt: null,
      transferRx: 0,
      transferTx: 0,
    });
  });

  test('tolerates an empty dump', () => {
    expect(parseWgDump('').size).toBe(0);
  });
});

describe('buildClientFullConfig', () => {
  const iface = {
    publicKey: 'serverPub=',
    serverPublicDomain: null,
    serverPublicIpV4: '203.0.113.5',
  } as never;
  const userConfig = {
    defaultDns: ['1.1.1.1'],
    defaultAllowedIps: ['0.0.0.0/0'],
  } as never;
  const client = {
    id: 3,
    privateKey: 'clientPriv=',
    preSharedKey: 'psk=',
    ipv4Address: '10.8.0.3',
    ipv6Address: 'fdcc::3',
    mtu: 1420,
    dns: null,
    allowedIps: null,
    persistentKeepalive: 25,
    preUp: '',
    postUp: '',
    preDown: '',
    postDown: '',
  } as never;
  const basePreset = {
    extPort: 51822,
    key: 'k',
    masking: 'MEDIA',
    obfuscateBytes: 0,
    dummy: 40,
    verbose: 'error',
    clientWgLocalPort: 14000,
    clientLocalPort: 1080,
    mediaSsrc: null,
  };

  test('WireGuard preset: WG config pointing to the preset local port plus obfuscator instance', () => {
    const config = buildClientFullConfig({
      iface,
      userConfig,
      client,
      preset: { ...basePreset, mode: 'WIREGUARD' } as never,
      enableIpv6: false,
      socks5Credentials: null,
    });
    expect(config).toContain('Endpoint = 127.0.0.1:14000');
    expect(config).toContain('Address = 10.8.0.3/32\n');
    expect(config).toContain(
      '[instance]\nsource-if = 127.0.0.1\nsource-lport = 14000'
    );
    expect(config).toContain('target = 203.0.113.5:51822');
    expect(config).toContain('obfuscate-bytes = 16');
  });

  test('SOCKS5 preset: obfuscator instance plus credentials, no WireGuard sections', () => {
    const config = buildClientFullConfig({
      iface,
      userConfig,
      client,
      preset: { ...basePreset, mode: 'SOCKS5', mediaSsrc: 42 } as never,
      enableIpv6: true,
      socks5Credentials: { login: 'abcde', password: 'fghij' },
    });
    expect(config).not.toContain('[Interface]');
    expect(config).toContain('mode = socks5\nrole = client');
    expect(config).toContain('media-ssrc = 42');
    expect(config.endsWith('[socks5]\nlogin = abcde\npassword = fghij\n')).toBe(
      true
    );
  });

  test('SOCKS5 preset without credentials is rejected', () => {
    expect(() =>
      buildClientFullConfig({
        iface,
        userConfig,
        client,
        preset: { ...basePreset, mode: 'SOCKS5' } as never,
        enableIpv6: true,
        socks5Credentials: null,
      })
    ).toThrow();
  });
});
