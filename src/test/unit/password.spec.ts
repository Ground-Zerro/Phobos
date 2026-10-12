import { expect, test, describe, vi } from 'vitest';
import argon2 from 'argon2';
import {
  CachedTokenVerifier,
  hashPassword,
  isPasswordValid,
  isValidPasswordHash,
} from '../../server/utils/password';

describe('password', () => {
  test('password', async () => {
    const hash = await hashPassword('password');

    await expect(isPasswordValid('password', hash)).resolves.toBe(true);
    await expect(isPasswordValid('wrong', hash)).resolves.toBe(false);

    expect(isValidPasswordHash('not a hash')).toBe(false);
    expect(isValidPasswordHash(hash)).toBe(true);

    expect(isValidPasswordHash(hash.replace('argon2', 'argon3'))).toBe(false);
  });

  test('cached token verifier', async () => {
    const verifier = new CachedTokenVerifier();
    const first = await hashPassword('token');
    const second = await hashPassword('other');
    const spy = vi.spyOn(argon2, 'verify');

    await expect(verifier.verify('token', first)).resolves.toBe(true);
    await expect(verifier.verify('token', first)).resolves.toBe(true);
    expect(spy).toHaveBeenCalledTimes(1);

    await expect(verifier.verify('wrong', first)).resolves.toBe(false);
    expect(spy).toHaveBeenCalledTimes(2);

    await expect(verifier.verify('token', second)).resolves.toBe(false);
    await expect(verifier.verify('other', second)).resolves.toBe(true);
    await expect(verifier.verify('token', first)).resolves.toBe(true);
    expect(spy).toHaveBeenCalledTimes(5);

    spy.mockRestore();
  });
});
