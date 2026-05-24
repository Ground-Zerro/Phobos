import { sql, relations } from 'drizzle-orm';
import { int, sqliteTable, text } from 'drizzle-orm/sqlite-core';

import { userConfig, hooks } from '../../schema';

export const wgInterface = sqliteTable('interfaces_table', {
  name: text().primaryKey(),
  device: text().notNull(),
  port: int().notNull().unique(),
  privateKey: text('private_key').notNull(),
  publicKey: text('public_key').notNull(),
  ipv4Cidr: text('ipv4_cidr').notNull(),
  ipv6Cidr: text('ipv6_cidr').notNull(),
  mtu: int().notNull(),
  enabled: int({ mode: 'boolean' }).notNull(),
  firewallEnabled: int('firewall_enabled', { mode: 'boolean' })
    .notNull()
    .default(false),
  obfuscatorExtPort: int('obfuscator_ext_port').notNull().default(51822),
  obfuscatorKey: text('obfuscator_key').notNull().default(''),
  obfuscatorMasking: text('obfuscator_masking', {
    enum: ['STUN', 'AUTO', 'NONE'],
  })
    .notNull()
    .default('STUN'),
  obfuscatorIdle: int('obfuscator_idle').notNull().default(300),
  obfuscatorDummy: int('obfuscator_dummy').notNull().default(10),
  serverPublicIpV4: text('server_public_ip_v4').notNull().default(''),
  serverPublicIpV6: text('server_public_ip_v6'),
  clientWgLocalPort: int('client_wg_local_port').notNull().default(13255),
  createdAt: text('created_at')
    .notNull()
    .default(sql`(CURRENT_TIMESTAMP)`),
  updatedAt: text('updated_at')
    .notNull()
    .default(sql`(CURRENT_TIMESTAMP)`)
    .$onUpdate(() => sql`(CURRENT_TIMESTAMP)`),
});

export const wgInterfaceRelations = relations(wgInterface, ({ one }) => ({
  hooks: one(hooks, {
    fields: [wgInterface.name],
    references: [hooks.id],
  }),
  userConfig: one(userConfig, {
    fields: [wgInterface.name],
    references: [userConfig.id],
  }),
}));
