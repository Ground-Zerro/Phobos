import { execFile as execFileCb } from 'node:child_process';
import {
  access,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { constants } from 'node:fs';
import { join, isAbsolute } from 'node:path';
import { tmpdir } from 'node:os';
import { promisify } from 'node:util';
import { isIP } from 'is-ip';
import { z } from 'zod';

const CERT_ROOT = '/app/certs';

const runOpenssl = promisify(execFileCb);

function openssl(args: string[], input?: string) {
  const child = runOpenssl('openssl', args, { encoding: 'utf8' });
  if (input !== undefined) child.child.stdin?.end(input);
  return child;
}

export const TlsModeSchema = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('self-signed') }),
  z.object({
    mode: z.literal('import'),
    cert: z.string().min(1),
    key: z.string().min(1),
  }),
  z.object({
    mode: z.literal('import-path'),
    certPath: z.string().min(1),
    keyPath: z.string().min(1),
  }),
  z.object({ mode: z.literal('skip') }),
]);

type TlsModeRequest = z.infer<typeof TlsModeSchema>;

async function storeCert(
  name: string,
  cert: string,
  key: string,
  origin: string
) {
  const dir = join(CERT_ROOT, name);
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, 'fullchain.pem'), cert, { mode: 0o644 });
  await writeFile(join(dir, 'privkey.pem'), key, { mode: 0o600 });
  await writeFile(join(dir, 'origin'), origin);
}

async function activateCert(name: string) {
  const activeLink = join(CERT_ROOT, 'active');
  await rm(activeLink, { force: true });
  await symlink(join(CERT_ROOT, name), activeLink);
}

async function generateSelfSigned(host: string) {
  const san = isIP(host) ? `IP:${host}` : `DNS:${host}`;
  const name = `self-${host.replace(/[^a-zA-Z0-9.-]/g, '_')}`;
  const workDir = await mkdtemp(join(tmpdir(), 'phobos-cert-'));
  const certPath = join(workDir, 'cert.pem');
  const keyPath = join(workDir, 'key.pem');

  try {
    await openssl([
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      keyPath,
      '-out',
      certPath,
      '-days',
      '3650',
      '-subj',
      `/CN=${host}`,
      '-addext',
      `subjectAltName=${san}`,
    ]);
    const [cert, key] = await Promise.all([
      readFile(certPath, 'utf8'),
      readFile(keyPath, 'utf8'),
    ]);
    await storeCert(name, cert, key, 'self-signed');
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }
  await activateCert(name);
}

async function importCert(certPem: string, keyPem: string) {
  await openssl(['x509', '-noout'], certPem);
  await openssl(['pkey', '-noout'], keyPem);

  const { stdout } = await openssl(
    ['x509', '-noout', '-subject', '-nameopt', 'multiline'],
    certPem
  );
  const cn = stdout
    .match(/commonName\s*=\s*(.+)/)?.[1]
    ?.trim()
    .replace(/[^a-zA-Z0-9.-]/g, '_');
  const name = `imported-${cn ?? 'cert'}`;

  await storeCert(name, certPem, keyPem, 'imported');
  await activateCert(name);
}

async function assertReadablePem(path: string, kind: 'certificate' | 'key') {
  if (!isAbsolute(path)) {
    throw new Error(`${kind} path must be absolute: ${path}`);
  }
  try {
    await access(path, constants.R_OK);
  } catch (e) {
    throw new Error(
      `Failed to read ${kind} file at ${path}: ${(e as Error).message}`
    );
  }
}

async function importCertFromPath(certPath: string, keyPath: string) {
  await assertReadablePem(certPath, 'certificate');
  await assertReadablePem(keyPath, 'key');
  await openssl(['x509', '-noout', '-in', certPath]);
  await openssl(['pkey', '-noout', '-in', keyPath]);

  const name = 'path-imported';
  const dir = join(CERT_ROOT, name);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  await symlink(certPath, join(dir, 'fullchain.pem'));
  await symlink(keyPath, join(dir, 'privkey.pem'));
  await writeFile(
    join(dir, 'origin'),
    `imported-path\ncert=${certPath}\nkey=${keyPath}\n`,
    { mode: 0o644 }
  );
  await activateCert(name);
}

function installCertificate(
  request: Exclude<TlsModeRequest, { mode: 'skip' }>,
  host: string
) {
  switch (request.mode) {
    case 'self-signed':
      return generateSelfSigned(host);
    case 'import':
      return importCert(request.cert, request.key);
    case 'import-path':
      return importCertFromPath(request.certPath, request.keyPath);
  }
}

export async function applyTlsMode(
  request: TlsModeRequest
): Promise<string | null> {
  if (request.mode === 'skip') {
    await Database.general.setAllowInsecureHttpLogin(true);
    return null;
  }

  await Database.general.setAllowInsecureHttpLogin(false);
  const { host } = await Database.userConfigs.get();

  try {
    await installCertificate(request, host);
  } catch (e) {
    const raw = e instanceof Error ? e.message : String(e);
    const firstLine = raw.split('\n').find((l) => l.trim().length > 0) ?? raw;
    throw createError({ statusCode: 400, statusMessage: firstLine });
  }

  const urlHost = host.includes(':') ? `[${host}]` : host;
  return `https://${urlHost}:${WG_ENV.PORT}/login`;
}

export function scheduleNodeRestart() {
  setTimeout(() => {
    process.exit(0);
  }, 500);
}
