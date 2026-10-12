import { sql } from 'drizzle-orm';
import { text } from 'drizzle-orm/sqlite-core';

export function timestamps() {
  return {
    createdAt: text('created_at')
      .notNull()
      .default(sql`(CURRENT_TIMESTAMP)`),
    updatedAt: text('updated_at')
      .notNull()
      .default(sql`(CURRENT_TIMESTAMP)`)
      .$onUpdate(() => sql`(CURRENT_TIMESTAMP)`),
  };
}
