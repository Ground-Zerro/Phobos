import { sql, relations } from 'drizzle-orm';
import { int, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

import { client } from '../../schema';

export const obfuscatorPreset = sqliteTable(
  'obfuscator_presets_table',
  {
    id: int().primaryKey({ autoIncrement: true }),
    name: text().notNull().unique(),
    isDefault: int('is_default', { mode: 'boolean' }).notNull().default(false),
    extPort: int('ext_port').notNull().unique(),
    key: text().notNull(),
    masking: text({ enum: ['STUN', 'MEDIA', 'AUTO', 'NONE'] })
      .notNull()
      .default('STUN'),
    idle: int().notNull().default(300),
    dummy: int().notNull().default(40),
    clientWgLocalPort: int('client_wg_local_port').notNull().default(13255),
    createdAt: text('created_at')
      .notNull()
      .default(sql`(CURRENT_TIMESTAMP)`),
    updatedAt: text('updated_at')
      .notNull()
      .default(sql`(CURRENT_TIMESTAMP)`)
      .$onUpdate(() => sql`(CURRENT_TIMESTAMP)`),
  },
  (t) => [
    uniqueIndex('uq_default_preset')
      .on(t.isDefault)
      .where(sql`${t.isDefault} = 1`),
  ]
);

export const obfuscatorPresetRelations = relations(
  obfuscatorPreset,
  ({ many }) => ({
    clients: many(client),
  })
);
