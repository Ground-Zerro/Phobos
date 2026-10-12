import type { DBType } from './sqlite';

export abstract class Repository<TStatements> {
  protected readonly db: DBType;
  protected readonly statements: TStatements;

  protected constructor(db: DBType, prepare: (db: DBType) => TStatements) {
    this.db = db;
    this.statements = prepare(db);
  }
}
