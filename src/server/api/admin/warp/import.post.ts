import { isIP } from 'is-ip';
import z from 'zod';
import { WarpManualSchema } from '#db/repositories/warp/types';
import { maskWarp } from '#db/repositories/warp/service';

function parseWgConfig(text: string): Record<string, Record<string, string>> {
  const result: Record<string, Record<string, string>> = {};
  let section = '';
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const sectionMatch = line.match(/^\[([^\]]+)\]$/);
    if (sectionMatch) {
      section = sectionMatch[1]!.toLowerCase();
      result[section] ??= {};
      continue;
    }
    const eqIdx = line.indexOf('=');
    if (eqIdx > 0 && section) {
      const key = line.slice(0, eqIdx).trim().toLowerCase();
      const value = line.slice(eqIdx + 1).trim();
      result[section]![key] = value;
    }
  }
  return result;
}

function extractAddresses(raw: string): { v4: string; v6: string } {
  let v4 = '';
  let v6 = '';
  for (const part of raw.split(',')) {
    const ip = part.split('/')[0]!.trim();
    if (ip.includes(':')) v6 = ip;
    else if (isIP(ip)) v4 = ip;
  }
  return { v4, v6 };
}

const RawImportSchema = z.object({
  config: z.string().min(1),
});

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const { config } = await readValidatedBody(
      event,
      validateZod(RawImportSchema, event)
    );

    const sections = parseWgConfig(config);
    const iface = sections['interface'] ?? {};
    const peer = sections['peer'] ?? {};

    const required = ['privatekey', 'address'] as const;
    const peerRequired = ['publickey', 'endpoint'] as const;

    for (const key of required) {
      if (!iface[key]) {
        throw createError({
          statusCode: 400,
          statusMessage: `Invalid WireGuard config: missing [Interface] ${key}`,
        });
      }
    }
    for (const key of peerRequired) {
      if (!peer[key]) {
        throw createError({
          statusCode: 400,
          statusMessage: `Invalid WireGuard config: missing [Peer] ${key}`,
        });
      }
    }

    const { v4, v6 } = extractAddresses(iface['address']!);

    if (!v4) {
      throw createError({
        statusCode: 400,
        statusMessage:
          'Invalid WireGuard config: no valid IPv4 address in Address field',
      });
    }

    const mtuRaw = iface['mtu'] ? Number.parseInt(iface['mtu'], 10) : 1280;
    const keepaliveRaw = peer['persistentkeepalive']
      ? Number.parseInt(peer['persistentkeepalive'], 10)
      : 25;

    const parsed = await validateZod(
      WarpManualSchema,
      event
    )({
      privateKey: iface['privatekey'],
      peerPublicKey: peer['publickey'],
      endpoint: peer['endpoint'],
      addressV4: v4,
      addressV6: v6,
      mtu: Number.isNaN(mtuRaw) ? 1280 : mtuRaw,
      dns: iface['dns'] ?? '',
      presharedKey: peer['presharedkey'] ?? '',
      persistentKeepalive: Number.isNaN(keepaliveRaw) ? 25 : keepaliveRaw,
    });

    if (!(await Database.warp.isRegistered())) {
      throw createError({
        statusCode: 400,
        statusMessage: 'WARP is not registered.',
      });
    }

    try {
      await WarpInterface.importConfig(parsed);
    } catch (e) {
      throw createError({
        statusCode: 400,
        statusMessage: (e as Error).message,
      });
    }

    const warp = await Database.warp.get();
    return maskWarp(warp);
  }
);
