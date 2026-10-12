import { relations } from 'drizzle-orm';
import { int, sqliteTable, text } from 'drizzle-orm/sqlite-core';

import { timestamps } from '../../timestamps';

import { client } from '../../schema';

export const user = sqliteTable('users_table', {
  id: int().primaryKey({ autoIncrement: true }),
  username: text().notNull().unique(),
  password: text().notNull(),
  email: text(),
  name: text().notNull(),
  role: int().$type<Role>().notNull(),
  totpKey: text('totp_key'),
  totpVerified: int('totp_verified', { mode: 'boolean' }).notNull(),
  enabled: int({ mode: 'boolean' }).notNull(),
  ...timestamps(),
});

export const usersRelations = relations(user, ({ many }) => ({
  clients: many(client),
}));
