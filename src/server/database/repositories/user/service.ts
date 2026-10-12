import { eq, sql } from 'drizzle-orm';
import { TOTP } from 'otpauth';
import { user } from './schema';
import type { UserType } from './types';
import { Repository } from '#db/repository';
import type { DBType } from '#db/sqlite';

type LoginResult =
  | { success: true; user: UserType }
  | {
      success: false;
      error:
        | 'INCORRECT_CREDENTIALS'
        | 'TOTP_REQUIRED'
        | 'USER_DISABLED'
        | 'INVALID_TOTP_CODE'
        | 'UNEXPECTED_ERROR';
    };

export function createTotp(username: string, secret: string) {
  return new TOTP({
    issuer: TOTP_ISSUER,
    label: username,
    algorithm: 'SHA1',
    digits: 6,
    period: 30,
    secret,
  });
}

function isTotpValid(username: string, secret: string, code: string) {
  return (
    createTotp(username, secret).validate({ token: code, window: 1 }) !== null
  );
}

function createPreparedStatement(db: DBType) {
  return {
    findById: db.query.user
      .findFirst({ where: eq(user.id, sql.placeholder('id')) })
      .prepare(),
    findByUsername: db.query.user
      .findFirst({ where: eq(user.username, sql.placeholder('username')) })
      .prepare(),
    update: db
      .update(user)
      .set({
        name: sql.placeholder('name') as never as string,
        email: sql.placeholder('email') as never as string,
      })
      .where(eq(user.id, sql.placeholder('id')))
      .prepare(),
    updateKey: db
      .update(user)
      .set({
        totpKey: sql.placeholder('key') as never as string,
        totpVerified: false,
      })
      .where(eq(user.id, sql.placeholder('id')))
      .prepare(),
  };
}

export class UserService extends Repository<
  ReturnType<typeof createPreparedStatement>
> {
  constructor(db: DBType) {
    super(db, createPreparedStatement);
  }

  get(id: ID) {
    return this.statements.findById.execute({ id });
  }

  getByUsername(username: string) {
    return this.statements.findByUsername.execute({ username });
  }

  async #requireWithPassword(id: ID, password: string) {
    const row = await this.get(id);
    if (!row) {
      throw new Error('User not found');
    }
    if (!(await isPasswordValid(password, row.password))) {
      throw new Error('Invalid password');
    }
    return row;
  }

  async create(username: string, password: string) {
    const hash = await hashPassword(password);

    return this.db.transaction(async (tx) => {
      const existing = await tx.query.user
        .findFirst({ where: eq(user.username, username) })
        .execute();
      if (existing) {
        throw new Error('User already exists');
      }

      const userCount = await tx.$count(user);

      await tx.insert(user).values({
        password: hash,
        username,
        email: null,
        name: 'Administrator',
        role: userCount === 0 ? roles.ADMIN : roles.CLIENT,
        totpVerified: false,
        enabled: true,
      });
    });
  }

  update(id: ID, name: string, email: string | null) {
    return this.statements.update.execute({ id, name, email });
  }

  async updatePassword(id: ID, currentPassword: string, newPassword: string) {
    const row = await this.#requireWithPassword(id, currentPassword);
    const hash = await hashPassword(newPassword);
    await this.db
      .update(user)
      .set({ password: hash })
      .where(eq(user.id, row.id))
      .execute();
  }

  updateTotpKey(id: ID, key: string | null) {
    return this.statements.updateKey.execute({ id, key });
  }

  async login(
    username: string,
    password: string,
    code: string | undefined
  ): Promise<LoginResult> {
    const row = await this.getByUsername(username);
    if (!row || !(await isPasswordValid(password, row.password))) {
      return { success: false, error: 'INCORRECT_CREDENTIALS' };
    }

    if (row.totpVerified) {
      if (!code) {
        return { success: false, error: 'TOTP_REQUIRED' };
      }
      if (!row.totpKey) {
        return { success: false, error: 'UNEXPECTED_ERROR' };
      }
      if (!isTotpValid(row.username, row.totpKey, code)) {
        return { success: false, error: 'INVALID_TOTP_CODE' };
      }
    }

    if (!row.enabled) {
      return { success: false, error: 'USER_DISABLED' };
    }

    return { success: true, user: row };
  }

  async verifyTotp(id: ID, code: string) {
    const row = await this.get(id);
    if (!row) {
      throw new Error('User not found');
    }
    if (!row.totpKey) {
      throw new Error('TOTP key is not set');
    }
    if (!isTotpValid(row.username, row.totpKey, code)) {
      throw new Error('Invalid TOTP code');
    }
    await this.db
      .update(user)
      .set({ totpVerified: true })
      .where(eq(user.id, id))
      .execute();
  }

  async deleteTotpKey(id: ID, currentPassword: string) {
    await this.#requireWithPassword(id, currentPassword);
    await this.db
      .update(user)
      .set({ totpKey: null, totpVerified: false })
      .where(eq(user.id, id))
      .execute();
  }
}
