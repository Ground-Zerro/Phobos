import { sqliteTable, text, int } from 'drizzle-orm/sqlite-core';

import { timestamps } from '../../timestamps';

export const general = sqliteTable('general_table', {
  id: int().primaryKey({ autoIncrement: false }).default(1),

  setupStep: int('setup_step').notNull(),

  sessionPassword: text('session_password').notNull(),
  sessionTimeout: int('session_timeout').notNull(),

  metricsPrometheus: int('metrics_prometheus', { mode: 'boolean' }).notNull(),
  metricsJson: int('metrics_json', { mode: 'boolean' }).notNull(),
  metricsPassword: text('metrics_password'),

  allowInsecureHttpLogin: int('allow_insecure_http_login', { mode: 'boolean' })
    .notNull()
    .default(false),

  ...timestamps(),
});
