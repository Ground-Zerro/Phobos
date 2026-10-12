import { eq } from 'drizzle-orm';
import { userConfig } from './schema';
import type { UserConfigUpdateType } from './types';
import { WG_INTERFACE_NAME } from '#db/schema';
import { Repository } from '#db/repository';
import type { DBType } from '#db/sqlite';

const byInterface = eq(userConfig.id, WG_INTERFACE_NAME);

function createPreparedStatement(db: DBType) {
  return {
    get: db.query.userConfig.findFirst({ where: byInterface }).prepare(),
  };
}

export class UserConfigService extends Repository<
  ReturnType<typeof createPreparedStatement>
> {
  constructor(db: DBType) {
    super(db, createPreparedStatement);
  }

  async get() {
    const row = await this.statements.get.execute();
    if (!row) {
      throw new Error('User config not found');
    }
    return row;
  }

  update(data: Partial<UserConfigUpdateType>) {
    return this.db.update(userConfig).set(data).where(byInterface).execute();
  }
}
