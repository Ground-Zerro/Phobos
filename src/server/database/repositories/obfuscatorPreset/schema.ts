import { sql, relations } from 'drizzle-orm';
import { int, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

import { timestamps } from '../../timestamps';

import { client } from '../../schema';
import {
  OBFUSCATION_MASKINGS,
  OBFUSCATION_MODES,
  OBFUSCATOR_VERBOSITY,
  PRESET_DEFAULTS,
} from '../../../../shared/utils/obfuscation';

export const obfuscatorPreset = sqliteTable(
  'obfuscator_presets_table',
  {
    id: int().primaryKey({ autoIncrement: true }),
    name: text().notNull().unique(),
    isDefault: int('is_default', { mode: 'boolean' }).notNull().default(false),
    mode: text({ enum: OBFUSCATION_MODES }).notNull().default('WIREGUARD'),
    extPort: int('ext_port').notNull().unique(),
    sourceIf: text('source_if').notNull(),
    target: text(),
    key: text().notNull(),
    masking: text({ enum: OBFUSCATION_MASKINGS })
      .notNull()
      .default(PRESET_DEFAULTS.masking),
    obfuscateBytes: int('obfuscate_bytes')
      .notNull()
      .default(PRESET_DEFAULTS.obfuscateBytes),
    dummy: int().notNull().default(PRESET_DEFAULTS.dummy),
    verbose: text({ enum: OBFUSCATOR_VERBOSITY })
      .notNull()
      .default(PRESET_DEFAULTS.verbose),
    clientWgLocalPort: int('client_wg_local_port')
      .notNull()
      .default(PRESET_DEFAULTS.clientWgLocalPort),
    mediaSsrc: int('media_ssrc'),
    clientLocalPort: int('client_local_port')
      .notNull()
      .default(PRESET_DEFAULTS.clientLocalPort),
    ...timestamps(),
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
