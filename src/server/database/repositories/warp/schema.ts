import { int, sqliteTable, text } from 'drizzle-orm/sqlite-core';

import { timestamps } from '../../timestamps';

export const warp = sqliteTable('warp_table', {
  id: int().primaryKey({ autoIncrement: false }).default(1),

  accessToken: text('access_token').notNull().default(''),
  deviceId: text('device_id').notNull().default(''),
  licenseKey: text('license_key').notNull().default(''),
  privateKey: text('private_key').notNull().default(''),
  clientId: text('client_id').notNull().default(''),

  peerPublicKey: text('peer_public_key').notNull().default(''),
  endpoint: text().notNull().default('engage.cloudflareclient.com:2408'),
  addressV4: text('address_v4').notNull().default(''),
  addressV6: text('address_v6').notNull().default(''),
  mtu: int().notNull().default(1280),
  presharedKey: text('preshared_key').notNull().default(''),
  dns: text().notNull().default(''),
  persistentKeepalive: int('persistent_keepalive').notNull().default(25),

  updateIntervalDays: int('update_interval_days').notNull().default(0),
  lastUpdateAt: text('last_update_at'),

  ...timestamps(),
});
