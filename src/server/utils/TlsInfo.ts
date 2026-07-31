import { readFileSync, existsSync } from 'node:fs';

const ORIGIN_PATH = '/app/certs/active/origin';
const FULLCHAIN_PATH = '/app/certs/active/fullchain.pem';
const PRIVKEY_PATH = '/app/certs/active/privkey.pem';

export type TlsOrigin = 'self-signed' | 'imported' | 'imported-path' | 'none';

function readOriginFile(): string[] | null {
  if (!existsSync(ORIGIN_PATH)) return null;
  try {
    return readFileSync(ORIGIN_PATH, 'utf8').split('\n');
  } catch {
    return null;
  }
}

export function readTlsOrigin(): TlsOrigin {
  const lines = readOriginFile();
  if (!lines) return 'none';
  const head = lines[0]?.trim();
  if (
    head === 'self-signed' ||
    head === 'imported' ||
    head === 'imported-path'
  ) {
    return head;
  }
  return 'none';
}

export function readTlsWatchedPaths(): {
  certPath: string;
  keyPath: string;
} | null {
  const lines = readOriginFile();
  if (!lines || lines[0]?.trim() !== 'imported-path') return null;

  let certPath = '';
  let keyPath = '';
  for (const raw of lines.slice(1)) {
    const line = raw.trim();
    if (line.startsWith('cert=')) certPath = line.slice(5);
    else if (line.startsWith('key=')) keyPath = line.slice(4);
  }

  if (!certPath || !keyPath) return null;
  return { certPath, keyPath };
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
