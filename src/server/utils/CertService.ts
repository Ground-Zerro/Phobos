import { execFileSync, execSync } from 'node:child_process';
import { createServer } from 'node:net';
import {
  writeFileSync,
  mkdirSync,
  unlinkSync,
  existsSync,
  readFileSync,
  symlinkSync,
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const CERT_ROOT = '/app/certs';
const ACME_TIMEOUT_MS = 180_000;
const ACME_HTTP_PORT_HINT_PATH = join(CERT_ROOT, 'acme-http-port');

function acmeEnv(home: string): NodeJS.ProcessEnv {
  const { DEBUG: _debug, ...rest } = process.env;
  return { ...rest, HOME: home };
}

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

function ensureAcme(acmeSh: string, home: string) {
  if (!existsSync(acmeSh)) {
    try {
      execSync('curl -s https://get.acme.sh | sh -s --', {
        stdio: 'pipe',
        timeout: ACME_TIMEOUT_MS,
        env: acmeEnv(home),
      });
    } catch (error) {
      throw new Error(formatAcmeError(error, 'Failed to install acme.sh'));
    }
  }
}

function isPortFree(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = createServer();
    server.once('error', () => resolve(false));
    server.once('listening', () => {
      server.close(() => resolve(true));
    });
    server.listen(port, '0.0.0.0');
  });
}

async function pickAcmeHttpPort(preferred = 80): Promise<number> {
  if (await isPortFree(preferred)) {
    return preferred;
  }

  for (let port = 8080; port <= 65535; port++) {
    // eslint-disable-next-line no-await-in-loop
    if (await isPortFree(port)) {
      return port;
    }
  }

  throw new Error('No free TCP port available for ACME standalone challenge');
}

function storeAcmeHttpPortHint(port: number) {
  try {
    writeFileSync(ACME_HTTP_PORT_HINT_PATH, `${port}\n`, { mode: 0o644 });
  } catch {
    // non-fatal metadata write
  }
}

function formatAcmeError(error: unknown, fallback: string): string {
  if (error && typeof error === 'object') {
    const err = error as {
      message?: string;
      stderr?: Buffer | string;
      stdout?: Buffer | string;
      signal?: string;
      killed?: boolean;
    };

    if (err.signal === 'SIGTERM' || err.killed) {
      return 'Let\'s Encrypt operation timed out. Check DNS and that TCP/80 is reachable from the internet.';
    }

    const stderr = err.stderr
      ? Buffer.isBuffer(err.stderr)
        ? err.stderr.toString('utf8')
        : String(err.stderr)
      : '';
    const stdout = err.stdout
      ? Buffer.isBuffer(err.stdout)
        ? err.stdout.toString('utf8')
        : String(err.stdout)
      : '';
    const details = [stderr, stdout, err.message ?? '']
      .map((s) => s.trim())
      .find((s) => s.length > 0);
    if (details) {
      return details.split('\n')[0] ?? fallback;
    }
  }

  return fallback;
}

function runAcme(acmeSh: string, args: string[], home: string, fallback: string) {
  try {
    execFileSync(acmeSh, args, {
      stdio: 'pipe',
      timeout: ACME_TIMEOUT_MS,
      maxBuffer: 1024 * 1024 * 8,
      env: acmeEnv(home),
    });
  } catch (error) {
    throw new Error(formatAcmeError(error, fallback));
  }
}

function acmeInstallCert(
  acmeSh: string,
  domain: string,
  certPath: string,
  keyPath: string,
  home: string
) {
  runAcme(acmeSh, [
    '--installcert', '-d', domain,
    '--fullchain-file', certPath,
    '--key-file', keyPath,
    '--reloadcmd', 'kill 1',
  ], home, 'Failed to install certificate files from acme.sh');

  runAcme(
    acmeSh,
    ['--upgrade', '--auto-upgrade'],
    home,
    'Failed to enable acme.sh auto-upgrade'
  );
}

export async function issueLetsEncrypt(domain: string) {
  const home = process.env.HOME ?? '/root';
  const acmeSh = `${home}/.acme.sh/acme.sh`;
  ensureAcme(acmeSh, home);

  const tmp = tmpdir();
  const certPath = join(tmp, `le-${domain}-cert.pem`);
  const keyPath = join(tmp, `le-${domain}-key.pem`);

  const httpPort = await pickAcmeHttpPort(80);
  storeAcmeHttpPortHint(httpPort);

  runAcme(
    acmeSh,
    ['--set-default-ca', '--server', 'letsencrypt', '--force'],
    home,
    'Failed to set Let\'s Encrypt as default ACME CA'
  );
  runAcme(acmeSh, [
    '--issue', '-d', domain,
    '--standalone', '--httpport', String(httpPort), '--force',
  ], home, `Let's Encrypt domain issuance failed (port ${httpPort}; check DNS and TCP/80 reachability)`);

  acmeInstallCert(acmeSh, domain, certPath, keyPath, home);

  const cert = readFileSync(certPath, 'utf8');
  const key = readFileSync(keyPath, 'utf8');
  const name = domain.replace(/[^a-zA-Z0-9.\-]/g, '_');

  storeCert(name, cert, key, 'letsencrypt');
  activateCert(name);
}

export async function issueLetsEncryptIp(ip: string) {
  if (!isIp(ip)) {
    throw new Error(
      `Let\'s Encrypt IP mode requires an IP in host settings, got "${ip}".`
    );
  }

  const httpPort = await pickAcmeHttpPort(80);
  storeAcmeHttpPortHint(httpPort);

  const home = process.env.HOME ?? '/root';
  const acmeSh = `${home}/.acme.sh/acme.sh`;
  ensureAcme(acmeSh, home);

  const tmp = tmpdir();
  const certPath = join(tmp, `le-${ip}-cert.pem`);
  const keyPath = join(tmp, `le-${ip}-key.pem`);

  runAcme(
    acmeSh,
    ['--set-default-ca', '--server', 'letsencrypt', '--force'],
    home,
    'Failed to set Let\'s Encrypt as default ACME CA'
  );
  runAcme(acmeSh, [
    '--issue', '-d', ip,
    '--standalone', '--httpport', String(httpPort),
    '--certificate-profile', 'shortlived', '--days', '6',
    '--force',
  ], home, `Let's Encrypt IP issuance failed (port ${httpPort}; check TCP/80 reachability and IP certificate availability)`);

  acmeInstallCert(acmeSh, ip, certPath, keyPath, home);

  const cert = readFileSync(certPath, 'utf8');
  const key = readFileSync(keyPath, 'utf8');
  const name = `ip-${ip.replace(/[^a-zA-Z0-9.\-]/g, '_')}`;

  storeCert(name, cert, key, 'letsencrypt-ip');
  activateCert(name);
}

export function scheduleNodeRestart() {
  setTimeout(() => {
    process.exit(0);
  }, 500);
}
