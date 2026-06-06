import { spawn, type ChildProcess } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import debug from 'debug';

import type { InterfaceType } from '#db/repositories/interface/types';
import type { ObfuscatorPresetType } from '#db/repositories/obfuscatorPreset/types';
import { OBFUSCATOR_PORT_MIN } from '#db/repositories/obfuscatorPreset/types';

const OBFUSCATOR_DEBUG = debug('Obfuscator');

const BINARY = '/usr/local/bin/wg-obfuscator';
const KEY_LENGTH_MIN = 200;
const KEY_LENGTH_MAX = 254;

function isPrivateIp(ip: string): boolean {
  return /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|127\.|169\.254\.)/.test(ip);
}

function randomKeyLength(): number {
  const span = KEY_LENGTH_MAX - KEY_LENGTH_MIN + 1;
  return KEY_LENGTH_MIN + (randomBytes(1)[0]! % span);
}

export function generateObfuscatorKey(length: number = randomKeyLength()): string {
  if (length < 1 || length > 255) {
    throw new Error('Key length must be 1..255');
  }
  return randomBytes(length * 2)
    .toString('base64')
    .replace(/[+/=]/g, '')
    .slice(0, length);
}

type RunningPreset = { child: ChildProcess; fingerprint: string };

class ObfuscatorService {
  #processes = new Map<number, RunningPreset>();

  buildArgs(preset: ObfuscatorPresetType, wgPort: number): string[] {
    return [
      '--source-if=0.0.0.0',
      `--source-lport=${preset.extPort}`,
      `--target=127.0.0.1:${wgPort}`,
      `--key=${preset.key}`,
      `--masking=${preset.masking}`,
      '--verbose=INFO',
      `--idle-timeout=${preset.idle}`,
      `--max-dummy=${preset.dummy}`,
    ];
  }

  fingerprint(preset: ObfuscatorPresetType, wgPort: number): string {
    return [
      preset.extPort,
      preset.key,
      preset.masking,
      preset.idle,
      preset.dummy,
      wgPort,
    ].join('|');
  }

  spawnPreset(preset: ObfuscatorPresetType, wgPort: number): void {
    const args = this.buildArgs(preset, wgPort);
    const child = spawn(BINARY, args, { stdio: 'inherit' });
    const fingerprint = this.fingerprint(preset, wgPort);
    this.#processes.set(preset.id, { child, fingerprint });

    OBFUSCATOR_DEBUG(
      `spawned preset ${preset.id} (${preset.name}) pid=${child.pid} port=${preset.extPort}`
    );

    child.on('exit', (code, signal) => {
      const current = this.#processes.get(preset.id);
      if (current?.child === child) {
        OBFUSCATOR_DEBUG(
          `preset ${preset.id} exited unexpectedly: code=${code} signal=${signal}`
        );
        this.#processes.delete(preset.id);
      }
    });

    child.on('error', (err) => {
      OBFUSCATOR_DEBUG(
        `preset ${preset.id} spawn error: ${(err as Error).message}`
      );
    });
  }

  killPreset(presetId: number): void {
    const entry = this.#processes.get(presetId);
    if (!entry) return;
    this.#processes.delete(presetId);

    const { child } = entry;
    try {
      child.kill('SIGTERM');
    } catch {
      // ignore: process may have already exited
    }
    setTimeout(() => {
      try {
        child.kill('SIGKILL');
      } catch {
        // ignore
      }
    }, 2000).unref();

    OBFUSCATOR_DEBUG(`killed preset ${presetId} pid=${child.pid}`);
  }

  async applyAll(): Promise<void> {
    const presets = await Database.obfuscatorPresets.list();
    const iface = await Database.interfaces.get();

    const desired = new Map(presets.map((p) => [p.id, p]));

    for (const id of [...this.#processes.keys()]) {
      if (!desired.has(id)) this.killPreset(id);
    }

    for (const preset of presets) {
      const current = this.#processes.get(preset.id);
      const want = this.fingerprint(preset, iface.port);
      if (current && current.fingerprint === want) continue;
      if (current) this.killPreset(preset.id);
      this.spawnPreset(preset, iface.port);
    }

    OBFUSCATOR_DEBUG(
      `applied ${presets.length} presets, ${this.#processes.size} processes running`
    );
  }

  async Shutdown(): Promise<void> {
    OBFUSCATOR_DEBUG('Shutting down obfuscator presets');
    for (const id of [...this.#processes.keys()]) this.killPreset(id);
    await exec(`pkill -f ${BINARY} || true`).catch(() => {});
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

  buildClientObfConf(preset: ObfuscatorPresetType, iface: InterfaceType): string {
    return [
      '[instance]',
      'source-if = 127.0.0.1',
      `source-lport = ${preset.clientWgLocalPort}`,
      `target = ${iface.serverPublicIpV4}:${preset.extPort}`,
      `key = ${preset.key}`,
      `masking = ${preset.masking}`,
      'verbose = INFO',
      `idle-timeout = ${preset.idle}`,
      `max-dummy = ${preset.dummy}`,
      '',
    ].join('\n');
  }

  async Startup(): Promise<void> {
    OBFUSCATOR_DEBUG('Starting Obfuscator...');

    const iface = await Database.interfaces.get();

    if (!iface.serverPublicIpV4) {
      const ipv4 = await this.detectPublicIpV4().catch(() => '');
      const ipv6 = iface.serverPublicIpV6 ?? (await this.detectPublicIpV6());
      if (ipv4 || ipv6 !== iface.serverPublicIpV6) {
        await Database.interfaces.update({
          serverPublicIpV4: ipv4,
          serverPublicIpV6: ipv6,
        });
      }
    }

    await Database.obfuscatorPresets.ensureDefault({
      extPort: OBFUSCATOR_PORT_MIN,
      key: generateObfuscatorKey(),
      masking: 'STUN',
      idle: 300,
      dummy: 40,
      clientWgLocalPort: 13255,
    });

    // Clean up any orphan wg-obfuscator processes left by a previous Node
    // instance (crash, SIGKILL, etc.) before spawning fresh per-preset processes.
    await exec(`pkill -f ${BINARY} || true`).catch(() => {});

    await this.applyAll();

    OBFUSCATOR_DEBUG('Obfuscator started');
  }
}

export const Obfuscator = new ObfuscatorService();

export default Obfuscator;
