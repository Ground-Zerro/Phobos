import { eq } from 'drizzle-orm';
import { hooks } from './schema';
import type { HooksUpdateType } from './types';
import { WG_INTERFACE_NAME } from '#db/schema';
import { Repository } from '#db/repository';
import type { DBType } from '#db/sqlite';

const byInterface = eq(hooks.id, WG_INTERFACE_NAME);

function createPreparedStatement(db: DBType) {
  return {
    get: db.query.hooks.findFirst({ where: byInterface }).prepare(),
  };
}

export class HooksService extends Repository<
  ReturnType<typeof createPreparedStatement>
> {
  constructor(db: DBType) {
    super(db, createPreparedStatement);
  }

  async get() {
    const row = await this.statements.get.execute();
    if (!row) {
      throw new Error('Hooks not found');
    }
    return row;
  }

  update(data: HooksUpdateType) {
    return this.db.update(hooks).set(data).where(byInterface).execute();
  }
}
