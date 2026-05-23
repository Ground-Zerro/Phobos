import { execFileSync } from 'node:child_process';
import {
  writeFileSync,
  mkdirSync,
  unlinkSync,
  existsSync,
  readFileSync,
  symlinkSync,
} from 'node:fs';
import { join, isAbsolute } from 'node:path';
import { tmpdir } from 'node:os';

const CERT_ROOT = '/app/certs';

function isIp(host: string): boolean {
  return /^(\d{1,3}\.){3}\d{1,3}$/.test(host) || /^[0-9a-fA-F:]+$/.test(host);
}

function storeCert(name: string, cert: string, key: string, origin: string) {
  const dir = join(CERT_ROOT, name);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'fullchain.pem'), cert, { mode: 0o644 });
  writeFileSync(join(dir, 'privkey.pem'), key, { mode: 0o600 });
  writeFileSync(join(dir, 'origin'), origin);
}

function activateCert(name: string) {
  const activeLink = join(CERT_ROOT, 'active');
  try { unlinkSync(activeLink); } catch {}
  symlinkSync(join(CERT_ROOT, name), activeLink);
}

export function generateSelfSigned(host: string) {
  const san = isIp(host) ? `IP:${host}` : `DNS:${host}`;
  const name = `self-${host.replace(/[^a-zA-Z0-9.\-]/g, '_')}`;
  const tmp = tmpdir();
  const certPath = join(tmp, `${name}-cert.pem`);
  const keyPath = join(tmp, `${name}-key.pem`);

  execFileSync('openssl', [
    'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', keyPath,
    '-out', certPath,
    '-days', '3650',
    '-subj', `/CN=${host}`,
    '-addext', `subjectAltName=${san}`,
  ], { stdio: 'pipe' });

  const cert = readFileSync(certPath, 'utf8');
  const key = readFileSync(keyPath, 'utf8');

  storeCert(name, cert, key, 'self-signed');
  activateCert(name);
}

export function importCert(certPem: string, keyPem: string) {
  execFileSync('openssl', ['x509', '-noout'], {
    input: certPem,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  execFileSync('openssl', ['pkey', '-noout'], {
    input: keyPem,
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  const subjectOutput = execFileSync(
    'openssl',
    ['x509', '-noout', '-subject', '-nameopt', 'multiline'],
    { input: certPem, stdio: ['pipe', 'pipe', 'pipe'] }
  ).toString();

  const cnMatch = subjectOutput.match(/commonName\s*=\s*(.+)/);
  const cn = cnMatch ? cnMatch[1]!.trim().replace(/[^a-zA-Z0-9.\-]/g, '_') : 'cert';
  const name = `imported-${cn}`;

  storeCert(name, certPem, keyPem, 'imported');
  activateCert(name);
}

function readPemFile(path: string, kind: 'certificate' | 'key'): string {
  if (!isAbsolute(path)) {
    throw new Error(`${kind} path must be absolute: ${path}`);
  }
  if (!existsSync(path)) {
    throw new Error(`${kind} file not found: ${path}`);
  }
  try {
    return readFileSync(path, 'utf8');
  } catch (e) {
    throw new Error(
      `Failed to read ${kind} file at ${path}: ${(e as Error).message}`
    );
  }
}

export function importCertFromPath(certPath: string, keyPath: string) {
  const certPem = readPemFile(certPath, 'certificate');
  const keyPem = readPemFile(keyPath, 'key');
  importCert(certPem, keyPem);
}

export function scheduleNodeRestart() {
  setTimeout(() => {
    process.exit(0);
  }, 500);
}
