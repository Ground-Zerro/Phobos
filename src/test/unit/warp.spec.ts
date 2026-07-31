import { describe, expect, test } from 'vitest';
import { warpClientTestExports } from '../../server/phobos/warp/client';

const { parseWarpError, parseRegistration } = warpClientTestExports;

describe('warp', () => {
  describe('parseWarpError', () => {
    test('extracts message from error envelope', () => {
      expect(parseWarpError('{"errors":[{"message":"Invalid license"}]}')).toBe(
        'Invalid license'
      );
    });

    test('returns empty string for non-envelope body', () => {
      expect(parseWarpError('not json')).toBe('');
      expect(parseWarpError('{"id":"abc"}')).toBe('');
      expect(parseWarpError('{"errors":[]}')).toBe('');
    });
  });

  describe('parseRegistration', () => {
    const validResponse = {
      id: 'device-123',
      token: 'token-abc',
      account: { license: 'license-xyz' },
      config: {
        client_id: 'AABB',
        interface: { addresses: { v4: '172.16.0.2', v6: '2606:4700:110::1' } },
        peers: [
          {
            public_key: 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=',
            endpoint: { host: 'engage.cloudflareclient.com:2408' },
          },
        ],
      },
    };

    test('maps a full response to registration', () => {
      const result = parseRegistration(validResponse, 'my-private-key');

      expect(result).toEqual({
        accessToken: 'token-abc',
        deviceId: 'device-123',
        licenseKey: 'license-xyz',
        privateKey: 'my-private-key',
        clientId: 'AABB',
        peerPublicKey: 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=',
        endpoint: 'engage.cloudflareclient.com:2408',
        addressV4: '172.16.0.2',
        addressV6: '2606:4700:110::1',
      });
    });

    test('throws when id, token or license missing', () => {
      expect(() =>
        parseRegistration({ ...validResponse, id: undefined }, 'k')
      ).toThrow();
      expect(() =>
        parseRegistration({ ...validResponse, token: undefined }, 'k')
      ).toThrow();
      expect(() =>
        parseRegistration({ ...validResponse, account: {} }, 'k')
      ).toThrow();
    });

    test('throws when peer public key or endpoint missing', () => {
      expect(() =>
        parseRegistration(
          { ...validResponse, config: { ...validResponse.config, peers: [] } },
          'k'
        )
      ).toThrow();
    });

    test('defaults missing optional addresses to empty strings', () => {
      const result = parseRegistration(
        {
          ...validResponse,
          config: {
            client_id: undefined,
            interface: { addresses: {} },
            peers: validResponse.config.peers,
          },
        },
        'k'
      );

      expect(result.clientId).toBe('');
      expect(result.addressV4).toBe('');
      expect(result.addressV6).toBe('');
    });
  });
});
