import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGzip } from 'node:zlib';
import debug from 'debug';
import tar from 'tar-stream';

import type { InterfaceType } from '#db/repositories/interface/types';
import { readTlsOrigin, isUntrustedTls } from '~~/server/utils/TlsInfo';

const PACKAGE_DEBUG = debug('PhobosPackage');

const PROD_BIN_DIR = '/app/phobos/bin';
const PROD_TEMPLATES_DIR = '/app/phobos/templates';

const ARCHITECTURES = [
  'x86_64',
  'aarch64',
  'armv7',
  'mips',
  'mipsel',
] as const;

const TEMPLATES = [
  'lib-client.sh',
  'install-obfuscator.sh',
  'install-wireguard.sh',
  'router-configure-wireguard.sh',
  'router-configure-wireguard-openwrt.sh',
  '3xui.sh',
  'detect-router-arch.sh',
  'phobos-uninstall.sh',
] as const;

const TEMPLATE_WITH_PLACEHOLDER = 'install-router.sh.template';

function normalizeLf(content: string): string {
  return content.replaceAll('\r\n', '\n');
}

function resolveBinDir(): string {
  if (existsSync(PROD_BIN_DIR)) return PROD_BIN_DIR;
  return fileURLToPath(
    new URL('../../phobos-obfuscator/bin', import.meta.url)
  );
}

function resolveTemplatesDir(): string {
  if (existsSync(PROD_TEMPLATES_DIR)) return PROD_TEMPLATES_DIR;
  return fileURLToPath(new URL('../phobos/templates', import.meta.url));
}

function clientSlug(name: string, id: ID): string {
  const base = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 32);
  return base || `client-${id}`;
}

function streamToBuffer(stream: NodeJS.ReadableStream): Promise<Buffer> {
  return new Promise((ok, fail) => {
    const chunks: Buffer[] = [];
    stream.on('data', (c: Buffer) => chunks.push(c));
    stream.on('end', () => ok(Buffer.concat(chunks)));
    stream.on('error', fail);
  });
}

class PhobosPackageService {
  #cache = new Map<ID, Buffer>();

  async build(clientId: ID): Promise<Buffer> {
    const cached = this.#cache.get(clientId);
    if (cached) return cached;

    const iface = await Database.interfaces.get();
    const userConfig = await Database.userConfigs.get();
    const client = await Database.clients.get(clientId);
    if (!client) throw new Error(`Client ${clientId} not found`);

    const slug = clientSlug(client.name, client.id);
    const pkgRoot = `phobos-${slug}`;

    const wgConf = wg.generateClientConfig(iface, userConfig, client, {
      enableIpv6: !WG_ENV.DISABLE_IPV6,
    });

    const obfConf = Obfuscator.buildClientObfConf(iface);

    const templatesDir = resolveTemplatesDir();
    const binDir = resolveBinDir();

    const pack = tar.pack();

    pack.entry({ name: `${pkgRoot}/${slug}.conf`, mode: 0o600 }, wgConf);
    pack.entry({ name: `${pkgRoot}/wg-obfuscator.conf`, mode: 0o600 }, obfConf);

    const installRouter = (
      await readFile(resolve(templatesDir, TEMPLATE_WITH_PLACEHOLDER), 'utf8')
    )
      .replaceAll('{{CLIENT_NAME}}', slug);
    pack.entry(
      { name: `${pkgRoot}/install-router.sh`, mode: 0o755 },
      normalizeLf(installRouter)
    );

    for (const file of TEMPLATES) {
      const content = normalizeLf(
        await readFile(join(templatesDir, file), 'utf8')
      );
      pack.entry(
        { name: `${pkgRoot}/${file}`, mode: 0o755 },
        content
      );
    }

    for (const arch of ARCHITECTURES) {
      const bin = join(binDir, `wg-obfuscator-${arch}`);
      if (existsSync(bin)) {
        const content = await readFile(bin);
        pack.entry(
          { name: `${pkgRoot}/bin/wg-obfuscator-${arch}`, mode: 0o755 },
          content
        );
      }
    }

    const readme = [
      'Phobos Client Package',
      `Client: ${client.name}`,
      `Slug: ${slug}`,
      `Built: ${new Date().toISOString()}`,
      '',
    ].join('\n');
    pack.entry({ name: `${pkgRoot}/README.txt` }, readme);

    pack.finalize();

    const gzipped = await streamToBuffer(pack.pipe(createGzip()));
    this.#cache.set(clientId, gzipped);
    PACKAGE_DEBUG(`built package for client ${clientId} (${gzipped.length} B)`);
    return gzipped;
  }

  invalidate(clientId?: ID): void {
    if (clientId === undefined) {
      this.#cache.clear();
      PACKAGE_DEBUG('cache fully invalidated');
    } else {
      this.#cache.delete(clientId);
      PACKAGE_DEBUG(`cache invalidated for client ${clientId}`);
    }
  }

  async installScript(token: string, origin: string): Promise<string> {
    const link = await Database.installLinks.getActiveByToken(token);
    if (!link) throw createError({ statusCode: 404 });

    const client = await Database.clients.get(link.id);
    if (!client) throw createError({ statusCode: 404 });

    const slug = clientSlug(client.name, client.id);
    const pkgUrl = `${origin}/api/install/${token}/package.tar.gz`;

    const untrusted =
      origin.startsWith('https://') && isUntrustedTls(readTlsOrigin());
    const curlFlags = untrusted ? '-fksSL' : '-fsSL';
    const wgetFlags = untrusted ? '-q --no-check-certificate' : '-q';

    return [
      '#!/bin/sh',
      'set -e',
      `url="${pkgUrl}"`,
      'dir="/tmp/phobos_install_$$"',
      'mkdir -p "$dir"',
      'echo "Downloading Phobos package..."',
      'if command -v curl >/dev/null 2>&1; then',
      `  curl ${curlFlags} -o "$dir/package.tar.gz" "$url"`,
      'else',
      `  wget ${wgetFlags} -O "$dir/package.tar.gz" "$url"`,
      'fi',
      'if [ ! -s "$dir/package.tar.gz" ]; then',
      '  echo "Download failed"; exit 1',
      'fi',
      'cd "$dir"',
      'tar xzf package.tar.gz',
      `cd "phobos-${slug}"`,
      'chmod +x install-router.sh',
      './install-router.sh',
      '',
    ].join('\n');
  }

  async getFilename(clientId: ID): Promise<string> {
    const client = await Database.clients.get(clientId);
    if (!client) throw new Error(`Client ${clientId} not found`);
    return `phobos-${clientSlug(client.name, client.id)}.tar.gz`;
  }
}

export const PhobosPackage = new PhobosPackageService();

export default PhobosPackage;
