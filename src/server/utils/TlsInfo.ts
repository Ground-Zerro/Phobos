import { readFileSync, existsSync } from 'node:fs';

const ORIGIN_PATH = '/app/certs/active/origin';
const FULLCHAIN_PATH = '/app/certs/active/fullchain.pem';
const PRIVKEY_PATH = '/app/certs/active/privkey.pem';

export type TlsOrigin = 'self-signed' | 'imported' | 'none';

export function readTlsOrigin(): TlsOrigin {
  if (!existsSync(ORIGIN_PATH)) return 'none';
  try {
    const v = readFileSync(ORIGIN_PATH, 'utf8').trim();
    if (v === 'self-signed' || v === 'imported') {
      return v;
    }
    return 'none';
  } catch {
    return 'none';
  }
}

export function isUntrustedTls(origin: TlsOrigin): boolean {
  return origin === 'self-signed';
}

export function hasActiveTlsCert(): boolean {
  return existsSync(FULLCHAIN_PATH) && existsSync(PRIVKEY_PATH);
}

export function isExternalTlsManaged(): boolean {
  return process.env.TLS_TERMINATION === 'external';
}
