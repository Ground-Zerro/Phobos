import { relations } from 'drizzle-orm';
import { int, sqliteTable, text } from 'drizzle-orm/sqlite-core';

import { timestamps } from '../../timestamps';

import { client } from '../../schema';

export const installLink = sqliteTable('install_links_table', {
  id: int()
    .primaryKey()
    .references(() => client.id, {
      onDelete: 'cascade',
      onUpdate: 'cascade',
    }),
  token: text().notNull().unique(),
  expiresAt: text('expires_at').notNull(),
  ...timestamps(),
});

export const installLinksRelations = relations(installLink, ({ one }) => ({
  client: one(client, {
    fields: [installLink.id],
    references: [client.id],
  }),
}));
