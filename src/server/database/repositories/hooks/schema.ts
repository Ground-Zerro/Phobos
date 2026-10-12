import { sqliteTable, text } from 'drizzle-orm/sqlite-core';

import { timestamps } from '../../timestamps';

import { wgInterface } from '../../schema';

export const hooks = sqliteTable('hooks_table', {
  id: text()
    .primaryKey()
    .references(() => wgInterface.name, {
      onDelete: 'cascade',
      onUpdate: 'cascade',
    }),
  preUp: text('pre_up').notNull(),
  postUp: text('post_up').notNull(),
  preDown: text('pre_down').notNull(),
  postDown: text('post_down').notNull(),
  ...timestamps(),
});
