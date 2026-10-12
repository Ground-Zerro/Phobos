import { createHash, timingSafeEqual } from 'node:crypto';
import argon2 from 'argon2';
import { deserialize } from '@phc/format';

export function isPasswordValid(
  password: string,
  hash: string
): Promise<boolean> {
  return argon2.verify(hash, password);
}

export class CachedTokenVerifier {
  #hash = '';
  #digest: Buffer | null = null;

  async verify(token: string, hash: string): Promise<boolean> {
    const digest = createHash('sha256').update(token).digest();
    if (
      this.#digest !== null &&
      this.#hash === hash &&
      timingSafeEqual(this.#digest, digest)
    ) {
      return true;
    }
    if (!(await isPasswordValid(token, hash))) {
      return false;
    }
    this.#hash = hash;
    this.#digest = digest;
    return true;
  }
}

export async function hashPassword(password: string): Promise<string> {
  return argon2.hash(password);
}

export function isValidPasswordHash(hash: string): boolean {
  try {
    const obj = deserialize(hash);

    if (obj.id !== 'argon2i' && obj.id !== 'argon2d' && obj.id !== 'argon2id') {
      return false;
    }

    return true;
  } catch {
    return false;
  }
}
