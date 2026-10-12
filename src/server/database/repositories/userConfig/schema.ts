import { int, sqliteTable, text } from 'drizzle-orm/sqlite-core';

import { timestamps } from '../../timestamps';

import { wgInterface } from '../../schema';

export const userConfig = sqliteTable('user_configs_table', {
  id: text()
    .primaryKey()
    .references(() => wgInterface.name, {
      onDelete: 'cascade',
      onUpdate: 'cascade',
    }),
  defaultMtu: int('default_mtu').notNull(),
  defaultPersistentKeepalive: int('default_persistent_keepalive').notNull(),
  defaultDns: text('default_dns', { mode: 'json' }).$type<string[]>().notNull(),
  defaultAllowedIps: text('default_allowed_ips', { mode: 'json' })
    .$type<string[]>()
    .notNull(),
  host: text().notNull(),
  ...timestamps(),
});
