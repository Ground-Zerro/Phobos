import { sql } from 'drizzle-orm';
import { general } from './schema';
import type { GeneralUpdateType } from './types';
import { Repository } from '#db/repository';
import type { DBType } from '#db/sqlite';

function createPreparedStatement(db: DBType) {
  return {
    get: db.query.general.findFirst().prepare(),
    updateSetupStep: db
      .update(general)
      .set({
        setupStep: sql.placeholder('setupStep') as never as number,
      })
      .prepare(),
  };
}

export class GeneralService extends Repository<
  ReturnType<typeof createPreparedStatement>
> {
  constructor(db: DBType) {
    super(db, createPreparedStatement);
  }

  async #get() {
    const row = await this.statements.get.execute();
    if (!row) {
      throw new Error('General Config not found');
    }
    return row;
  }

  async getSetupStep() {
    const { setupStep } = await this.#get();
    return { step: setupStep, done: setupStep === 0 };
  }

  setSetupStep(step: number) {
    return this.statements.updateSetupStep.execute({ setupStep: step });
  }

  async getSessionConfig() {
    const row = await this.#get();
    return {
      sessionPassword: row.sessionPassword,
      sessionTimeout: row.sessionTimeout,
      allowInsecureHttpLogin: row.allowInsecureHttpLogin,
    };
  }

  setAllowInsecureHttpLogin(allowed: boolean) {
    return this.db
      .update(general)
      .set({ allowInsecureHttpLogin: allowed })
      .execute();
  }

  async getMetricsConfig() {
    const row = await this.#get();
    return {
      prometheus: row.metricsPrometheus,
      json: row.metricsJson,
      password: row.metricsPassword,
    };
  }

  async getConfig() {
    const row = await this.#get();
    return {
      sessionTimeout: row.sessionTimeout,
      metricsPrometheus: row.metricsPrometheus,
      metricsJson: row.metricsJson,
      metricsPasswordSet: row.metricsPassword != null,
    };
  }

  async update(data: GeneralUpdateType) {
    const metricsPassword = data.metricsPassword
      ? await hashPassword(data.metricsPassword)
      : undefined;
    return this.db
      .update(general)
      .set({ ...data, metricsPassword })
      .execute();
  }
}
