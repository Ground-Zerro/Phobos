import { sql } from 'drizzle-orm';
import { general } from './schema';
import type { GeneralUpdateType } from './types';
import type { DBType } from '#db/sqlite';

function createPreparedStatement(db: DBType) {
  return {
    getSetupStep: db.query.general
      .findFirst({
        columns: {
          setupStep: true,
        },
      })
      .prepare(),
    getAllowInsecureHttpLogin: db.query.general
      .findFirst({
        columns: {
          allowInsecureHttpLogin: true,
        },
      })
      .prepare(),
    getSessionConfig: db.query.general
      .findFirst({
        columns: {
          sessionPassword: true,
          sessionTimeout: true,
          allowInsecureHttpLogin: true,
        },
      })
      .prepare(),
    getMetricsConfig: db.query.general
      .findFirst({
        columns: {
          metricsPrometheus: true,
          metricsJson: true,
          metricsPassword: true,
        },
      })
      .prepare(),
    getConfig: db.query.general
      .findFirst({
        columns: {
          sessionTimeout: true,
          metricsPrometheus: true,
          metricsJson: true,
          metricsPassword: true,
        },
      })
      .prepare(),
    updateSetupStep: db
      .update(general)
      .set({
        setupStep: sql.placeholder('setupStep') as never as number,
      })
      .prepare(),
  };
}

export class GeneralService {
  #db: DBType;
  #statements: ReturnType<typeof createPreparedStatement>;

  constructor(db: DBType) {
    this.#db = db;
    this.#statements = createPreparedStatement(db);
  }

  /**
   * @throws
   */
  async getSetupStep() {
    const result = await this.#statements.getSetupStep.execute();

    if (!result) {
      throw new Error('General Config not found');
    }

    return { step: result.setupStep, done: result.setupStep === 0 };
  }

  setSetupStep(step: number) {
    return this.#statements.updateSetupStep.execute({ setupStep: step });
  }

  /**
   * @throws
   */
  async getSessionConfig() {
    const result = await this.#statements.getSessionConfig.execute();

    if (!result) {
      throw new Error('General Config not found');
    }

    return {
      sessionPassword: result.sessionPassword,
      sessionTimeout: result.sessionTimeout,
      allowInsecureHttpLogin: result.allowInsecureHttpLogin,
    };
  }

  /** For /api/information etc. — avoids loading session secrets. */
  async getAllowInsecureHttpLogin() {
    const row = await this.#statements.getAllowInsecureHttpLogin.execute();
    return row?.allowInsecureHttpLogin ?? false;
  }

  setAllowInsecureHttpLogin(allowed: boolean) {
    return this.#db
      .update(general)
      .set({ allowInsecureHttpLogin: allowed })
      .execute();
  }

  /**
   * @throws
   */
  async getMetricsConfig() {
    const result = await this.#statements.getMetricsConfig.execute();

    if (!result) {
      throw new Error('General Config not found');
    }

    return {
      prometheus: result.metricsPrometheus,
      json: result.metricsJson,
      password: result.metricsPassword,
    };
  }

  async update(data: GeneralUpdateType) {
    if (data.metricsPassword) {
      data.metricsPassword = await hashPassword(data.metricsPassword);
    }

    return this.#db.update(general).set(data).execute();
  }

  async getConfig() {
    const result = await this.#statements.getConfig.execute();

    if (!result) {
      throw new Error('General Config not found');
    }

    return {
      sessionTimeout: result.sessionTimeout,
      metricsPrometheus: result.metricsPrometheus,
      metricsJson: result.metricsJson,
      metricsPasswordSet: result.metricsPassword != null,
    };
  }
}
