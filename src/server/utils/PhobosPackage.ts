import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGzip } from 'node:zlib';
import tar from 'tar-stream';
import { createLogger } from './logger';

import { buildSocks5ObfConf, buildWireguardObfConf } from './clientConfig';
import { readTlsOrigin, isUntrustedTls } from '~~/server/utils/TlsInfo';

const PACKAGE_DEBUG = createLogger('PhobosPackage');

const PROD_BIN_DIR = '/app/phobos/bin';
const PROD_TEMPLATES_DIR = '/app/phobos/templates';

const ARCHITECTURES = ['x86_64', 'aarch64', 'armv7', 'mips', 'mipsel'] as const;

const TEMPLATES = [
  'lib-client.sh',
  'install-obfuscator.sh',
  'install-wireguard.sh',
  'router-configure-wireguard.sh',
  'router-configure-wireguard-openwrt.sh',
  'detect-router-arch.sh',
  'phobos-uninstall.sh',
] as const;

const SOCKS5_TEMPLATES = [
  'lib-client.sh',
  'install-obfuscator.sh',
  'install-wireguard.sh',
  'router-configure-socks5-keenetic.sh',
  'router-configure-socks5-openwrt.sh',
  'detect-router-arch.sh',
  'phobos-uninstall.sh',
] as const;

const TEMPLATE_WITH_PLACEHOLDER = 'install-router.sh.template';
const PACKAGE_CACHE_LIMIT = 8;

function normalizeLf(content: string): string {
  return content.replaceAll('\r\n', '\n');
}

function resolveBinDir(): string {
  if (existsSync(PROD_BIN_DIR)) return PROD_BIN_DIR;
  return fileURLToPath(new URL('../../phobos-obfuscator/bin', import.meta.url));
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

function readme(clientName: string, slug: string, isSocks5: boolean): string {
  const header = [
    isSocks5 ? 'Phobos Client Package (SOCKS5)' : 'Phobos Client Package',
    `Client: ${clientName}`,
    `Slug: ${slug}`,
    `Built: ${new Date().toISOString()}`,
    '',
    'If the router architecture is detected incorrectly, run',
    './detect-router-arch.sh to see how it was determined.',
    '',
  ];
  if (!isSocks5) {
    return header.join('\n');
  }
  return [
    ...header,
    'This client is assigned a SOCKS5-mode obfuscator preset, not WireGuard.',
    'On Keenetic routers, ./install-router.sh sets up the local obfuscator',
    'and a native SOCKS5 Proxy interface automatically. On other platforms,',
    'run the matching wg-obfuscator binary from bin/ with',
    'wg-socks5-obfuscator.conf (via -c) to get a local SOCKS5 proxy, then',
    "configure the login/password shown on this client's page in your",
    'SOCKS5 application.',
    '',
  ].join('\n');
}

function streamToBuffer(stream: NodeJS.ReadableStream): Promise<Buffer> {
  return new Promise((ok, fail) => {
    const chunks: Buffer[] = [];
    stream.on('data', (c: Buffer) => chunks.push(c));
    stream.on('end', () => ok(Buffer.concat(chunks)));
    stream.on('error', fail);
  });
}

type StaticAssets = {
  installRouter: string;
  templates: ReadonlyMap<string, string>;
  binaries: readonly { arch: string; content: Buffer }[];
};

async function loadStaticAssets(): Promise<StaticAssets> {
  const templatesDir = resolveTemplatesDir();
  const binDir = resolveBinDir();
  const templateNames = [...new Set([...TEMPLATES, ...SOCKS5_TEMPLATES])];

  const [installRouter, templateContents, binaries] = await Promise.all([
    readFile(join(templatesDir, TEMPLATE_WITH_PLACEHOLDER), 'utf8'),
    Promise.all(
      templateNames.map(async (name) => {
        const content = await readFile(join(templatesDir, name), 'utf8');
        return [name, normalizeLf(content)] as const;
      })
    ),
    Promise.all(
      ARCHITECTURES.filter((arch) =>
        existsSync(join(binDir, `wg-obfuscator-${arch}`))
      ).map(async (arch) => ({
        arch,
        content: await readFile(join(binDir, `wg-obfuscator-${arch}`)),
      }))
    ),
  ]);

  return {
    installRouter: normalizeLf(installRouter),
    templates: new Map(templateContents),
    binaries,
  };
}

class PhobosPackageService {
  #cache = new Map<ID, Buffer>();
  #assets: Promise<StaticAssets> | null = null;

  #staticAssets(): Promise<StaticAssets> {
    this.#assets ??= loadStaticAssets().catch((error: unknown) => {
      this.#assets = null;
      throw error;
    });
    return this.#assets;
  }

  #cached(clientId: ID): Buffer | undefined {
    const cached = this.#cache.get(clientId);
    if (cached) {
      this.#cache.delete(clientId);
      this.#cache.set(clientId, cached);
    }
    return cached;
  }

  #remember(clientId: ID, archive: Buffer): void {
    this.#cache.set(clientId, archive);
    if (this.#cache.size > PACKAGE_CACHE_LIMIT) {
      const oldest = this.#cache.keys().next().value!;
      this.#cache.delete(oldest);
    }
  }

  async build(clientId: ID): Promise<Buffer> {
    const cached = this.#cached(clientId);
    if (cached) return cached;

    const iface = await Database.interfaces.get();
    const userConfig = await Database.userConfigs.get();
    const client = await Database.clients.get(clientId);
    if (!client) throw new Error(`Client ${clientId} not found`);

    const preset = await Database.obfuscatorPresets.getForClient(
      client.presetId ?? null
    );
    const assets = await this.#staticAssets();

    const slug = clientSlug(client.name, client.id);
    const pkgRoot = `phobos-${slug}`;
    const pack = tar.pack();
    const isSocks5 = preset.mode === 'SOCKS5';

    if (isSocks5) {
      pack.entry(
        { name: `${pkgRoot}/wg-socks5-obfuscator.conf`, mode: 0o600 },
        buildSocks5ObfConf(preset, iface)
      );

      const { login, password } =
        await Database.clients.ensureSocks5Credentials(clientId);
      pack.entry(
        { name: `${pkgRoot}/socks5-credentials.env`, mode: 0o600 },
        [`SOCKS5_LOGIN='${login}'`, `SOCKS5_PASSWORD='${password}'`, ''].join(
          '\n'
        )
      );
    } else {
      pack.entry(
        { name: `${pkgRoot}/${slug}.conf`, mode: 0o600 },
        wg.generateClientConfig(iface, userConfig, client, {
          enableIpv6: !WG_ENV.DISABLE_IPV6,
          clientWgLocalPort: preset.clientWgLocalPort,
        })
      );
      pack.entry(
        { name: `${pkgRoot}/wg-obfuscator.conf`, mode: 0o600 },
        buildWireguardObfConf(preset, iface)
      );
    }

    pack.entry(
      { name: `${pkgRoot}/install-router.sh`, mode: 0o755 },
      assets.installRouter
        .replaceAll('{{CLIENT_NAME}}', slug)
        .replaceAll('{{PROTOCOL}}', isSocks5 ? 'socks5' : 'wireguard')
    );

    for (const file of isSocks5 ? SOCKS5_TEMPLATES : TEMPLATES) {
      pack.entry(
        { name: `${pkgRoot}/${file}`, mode: 0o755 },
        assets.templates.get(file)!
      );
    }

    for (const { arch, content } of assets.binaries) {
      pack.entry(
        { name: `${pkgRoot}/bin/wg-obfuscator-${arch}`, mode: 0o755 },
        content
      );
    }

    pack.entry(
      { name: `${pkgRoot}/README.txt` },
      readme(client.name, slug, isSocks5)
    );
    pack.finalize();

    const gzipped = await streamToBuffer(pack.pipe(createGzip()));
    this.#remember(clientId, gzipped);
    PACKAGE_DEBUG(
      `built ${preset.mode} package for client ${clientId} (${gzipped.length} B)`
    );
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

  installScript(
    client: { name: string; id: ID },
    token: string,
    origin: string
  ): string {
    const slug = clientSlug(client.name, client.id);
    const pkgUrl = `${origin}/api/install/${token}/package.tar.gz`;

    const untrusted =
      origin.startsWith('https://') && isUntrustedTls(readTlsOrigin());
    const curlFlags = untrusted ? '-fksSL' : '-fsSL';
    const wgetFlags = untrusted ? '-q --no-check-certificate' : '-q';

    const downloadSteps = [
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
    ];

    return [
      ...downloadSteps,
      'chmod +x install-router.sh',
      './install-router.sh',
      '',
    ].join('\n');
  }

  filename(client: { name: string; id: ID }): string {
    return `phobos-${clientSlug(client.name, client.id)}.tar.gz`;
  }
}

export const PhobosPackage = new PhobosPackageService();
