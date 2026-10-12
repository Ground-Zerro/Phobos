import { defineCommand } from 'citty';
import { consola } from 'consola';
import { eq } from 'drizzle-orm';

import { buildClientFullConfig } from '../../server/utils/clientConfig';
import { resolvePreset } from '../../server/database/repositories/obfuscatorPreset/resolve';
import { encodeQRCodeTerm } from '../../server/utils/qr';
import { db, schema } from '../db';

export default defineCommand({
  meta: {
    name: 'clients:qr',
    description: 'Generate QR code for a client',
  },
  args: {
    id: {
      required: true,
      type: 'positional',
    },
    ipv6: {
      required: false,
      type: 'boolean',
      default: process.env.DISABLE_IPV6 !== 'true',
    },
  },
  async run(ctx) {
    const clientId = Number(ctx.args.id);

    if (Number.isNaN(clientId)) {
      consola.error('Invalid client ID');
      return;
    }

    consola.info('Generating QR code for client...');

    const wgInterface = await db.query.wgInterface.findFirst({
      where: eq(schema.wgInterface.name, schema.WG_INTERFACE_NAME),
    });
    if (!wgInterface) {
      consola.error('WireGuard interface not found');
      return;
    }

    const userConfig = await db.query.userConfig.findFirst({
      where: eq(schema.userConfig.id, schema.WG_INTERFACE_NAME),
    });
    if (!userConfig) {
      consola.error('User config not found');
      return;
    }

    const client = await db.query.client.findFirst({
      where: eq(schema.client.id, clientId),
    });
    if (!client) {
      consola.error(`Client with ID ${clientId} not found`);
      return;
    }

    const preset = await resolvePreset(db, client.presetId);
    if (!preset) {
      consola.error('No default obfuscator preset configured');
      return;
    }

    const socks5Credentials =
      client.socks5Login && client.socks5Password
        ? { login: client.socks5Login, password: client.socks5Password }
        : null;
    if (preset.mode === 'SOCKS5' && !socks5Credentials) {
      consola.error(
        'SOCKS5 credentials are not generated yet; open the client in the web UI first'
      );
      return;
    }

    const config = buildClientFullConfig({
      iface: wgInterface,
      userConfig,
      client,
      preset,
      enableIpv6: ctx.args.ipv6,
      socks5Credentials,
    });

    consola.log(encodeQRCodeTerm(config));
  },
});
