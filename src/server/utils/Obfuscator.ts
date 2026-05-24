import { writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import debug from 'debug';

import type { InterfaceType } from '#db/repositories/interface/types';

const OBFUSCATOR_DEBUG = debug('Obfuscator');

const ARGS_PATH = '/run/wg-obfuscator.args';
const SERVICE_DIR = '/run/service/wg-obfuscator';
const DEFAULT_KEY_LENGTH = 16;

function isPrivateIp(ip: string): boolean {
  return /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|127\.|169\.254\.)/.test(ip);
}

class ObfuscatorService {
  buildArgs(iface: InterfaceType): string[] {
    return [
      `--source-if=0.0.0.0`,
      `--source-lport=${iface.obfuscatorExtPort}`,
      `--target=127.0.0.1:${iface.port}`,
      `--key=${iface.obfuscatorKey}`,
      `--masking=${iface.obfuscatorMasking}`,
      `--verbose=INFO`,
      `--idle-timeout=${iface.obfuscatorIdle}`,
      `--max-dummy=${iface.obfuscatorDummy}`,
    ];
  }

  async writeArgs(iface: InterfaceType): Promise<void> {
    const args = this.buildArgs(iface);
    await writeFile(ARGS_PATH, args.join('\n') + '\n', { mode: 0o600 });
    OBFUSCATOR_DEBUG(`wrote args to ${ARGS_PATH}`);
  }

  async restart(): Promise<void> {
    if (!existsSync(SERVICE_DIR)) {
      OBFUSCATOR_DEBUG('s6 service not available, skipping restart');
      return;
    }
    await exec(`/command/s6-svc -r ${SERVICE_DIR}`);
    OBFUSCATOR_DEBUG('s6-svc -r issued');
  }

  generateKey(length: number): string {
    if (length < 1 || length > 255) {
      throw new Error('Key length must be 1..255');
    }
    return randomBytes(length * 2)
      .toString('base64')
      .replace(/[+/=]/g, '')
      .slice(0, length);
  }

  async detectPublicIpV4(): Promise<string> {
    const envIp = process.env.WG_HOST;
    if (envIp && /^\d+\.\d+\.\d+\.\d+$/.test(envIp)) return envIp;

    const route = await exec('ip route');
    const iface = route.match(/^default.+dev\s+(\S+)/m)?.[1];
    if (iface) {
      const out = await exec(`ip -4 addr show dev ${iface} scope global`);
      const ip = out.match(/inet\s+(\d+\.\d+\.\d+\.\d+)/)?.[1];
      if (ip && !isPrivateIp(ip)) return ip;
    }

    const pub = await exec('curl -sf --max-time 5 https://api.ipify.org').catch(() => '');
    if (pub && /^\d+\.\d+\.\d+\.\d+$/.test(pub.trim())) return pub.trim();

    throw new Error('Cannot detect public IPv4. Set WG_HOST env variable.');
  }

  async detectPublicIpV6(): Promise<string | null> {
    try {
      const route = await exec('ip route');
      const iface = route.match(/^default.+dev\s+(\S+)/m)?.[1];
      if (!iface) return null;

      const out = await exec(`ip -6 addr show dev ${iface} scope global`);
      const ipv6 = out
        .match(/inet6\s+([0-9a-f:]+)/gi)
        ?.map((l) => l.replace(/^inet6\s+/i, ''))
        .find((addr) => !/^f[cd]/i.test(addr));
      return ipv6 ?? null;
    } catch {
      return null;
    }
  }

  async findFreePort(min = 1024, max = 65535): Promise<number> {
    let used = '';
    try {
      used = await exec('ss -ulnp');
    } catch {
      used = '';
    }
    const taken = new Set(
      [...used.matchAll(/:(\d+)\s/g)].map((m) => Number(m[1]))
    );

    for (let i = 0; i < 100; i++) {
      const port = Math.floor(Math.random() * (max - min + 1)) + min;
      if (!taken.has(port)) return port;
    }
    throw new Error('No free UDP port in range');
  }

  buildClientObfConf(iface: InterfaceType): string {
    return [
      '[instance]',
      'source-if = 127.0.0.1',
      `source-lport = ${iface.clientWgLocalPort}`,
      `target = ${iface.serverPublicIpV4}:${iface.obfuscatorExtPort}`,
      `key = ${iface.obfuscatorKey}`,
      `masking = ${iface.obfuscatorMasking}`,
      'verbose = INFO',
      `idle-timeout = ${iface.obfuscatorIdle}`,
      `max-dummy = ${iface.obfuscatorDummy}`,
      '',
    ].join('\n');
  }

  async apply(iface: InterfaceType): Promise<void> {
    await this.writeArgs(iface);
    await this.restart();
  }

  async Startup(): Promise<void> {
    OBFUSCATOR_DEBUG('Starting Obfuscator...');

    let iface = await Database.interfaces.get();

    const envPortRaw = Number(process.env.OBF_PORT);
    const envPort =
      Number.isFinite(envPortRaw) && envPortRaw >= 1024 && envPortRaw <= 65535
        ? envPortRaw
        : null;

    const needsInit =
      !iface.obfuscatorKey ||
      !iface.serverPublicIpV4 ||
      !iface.obfuscatorExtPort ||
      (envPort !== null && envPort !== iface.obfuscatorExtPort);

    if (needsInit) {
      OBFUSCATOR_DEBUG('First-run initialization');

      const port =
        envPort ?? iface.obfuscatorExtPort ?? (await this.findFreePort());
      const key = iface.obfuscatorKey || this.generateKey(DEFAULT_KEY_LENGTH);
      const ipv4 =
        iface.serverPublicIpV4 || (await this.detectPublicIpV4().catch(() => ''));
      const ipv6 = iface.serverPublicIpV6 ?? (await this.detectPublicIpV6());

      await Database.interfaces.update({
        obfuscatorExtPort: port,
        obfuscatorKey: key,
        obfuscatorMasking: iface.obfuscatorMasking,
        obfuscatorIdle: iface.obfuscatorIdle,
        obfuscatorDummy: iface.obfuscatorDummy,
        serverPublicIpV4: ipv4,
        serverPublicIpV6: ipv6,
        clientWgLocalPort: iface.clientWgLocalPort,
      });
      iface = await Database.interfaces.get();
    }

    await this.apply(iface);

    OBFUSCATOR_DEBUG('Obfuscator started');
  }
}

export const Obfuscator = new ObfuscatorService();

export default Obfuscator;
