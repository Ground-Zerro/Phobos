import { randomBytes, createHash } from 'node:crypto';
import { eq, sql } from 'drizzle-orm';
import { installLink } from './schema';
import type { DBType } from '#db/sqlite';

const TTL_MS = 5 * 60 * 1000;

function createPreparedStatement(db: DBType) {
  return {
    delete: db
      .delete(installLink)
      .where(eq(installLink.id, sql.placeholder('id')))
      .prepare(),
    create: db
      .insert(installLink)
      .values({
        id: sql.placeholder('id'),
        token: sql.placeholder('token'),
        expiresAt: sql.placeholder('expiresAt'),
      })
      .onConflictDoUpdate({
        target: installLink.id,
        set: {
          token: sql.placeholder('token') as never as string,
          expiresAt: sql.placeholder('expiresAt') as never as string,
        },
      })
      .prepare(),
    findByToken: db.query.installLink
      .findFirst({
        where: eq(installLink.token, sql.placeholder('token')),
      })
      .prepare(),
  };
}

export class InstallLinkService {
  #db: DBType;
  #statements: ReturnType<typeof createPreparedStatement>;

  constructor(db: DBType) {
    this.#db = db;
    this.#statements = createPreparedStatement(db);
  }

  delete(id: ID) {
    return this.#statements.delete.execute({ id });
  }

  getByToken(token: string) {
    return this.#statements.findByToken.execute({ token });
  }

  async getActiveByToken(token: string) {
    const link = await this.#statements.findByToken.execute({ token });
    if (!link) {
      return null;
    }

    if (new Date(link.expiresAt).getTime() < Date.now()) {
      await this.#statements.delete.execute({ id: link.id });
      return null;
    }

    return link;
  }

  async generate(id: ID) {
    const token = createHash('sha256')
      .update(randomBytes(32))
      .digest('hex')
      .slice(0, 32);
    const expiresAt = new Date(Date.now() + TTL_MS).toISOString();
    await this.#db.delete(installLink).where(eq(installLink.id, id)).execute();
    await this.#statements.create.execute({ id, token, expiresAt });
    return { token, expiresAt };
  }
}
