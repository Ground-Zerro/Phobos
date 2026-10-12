import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';

import * as schema from '../server/database/schema';
import { DB_URL } from '../server/database/url';

const client = createClient({ url: DB_URL });
export const db = drizzle({ client, schema });

export { schema };
