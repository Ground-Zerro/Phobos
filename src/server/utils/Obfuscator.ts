import { spawn, type ChildProcess } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import fs from 'node:fs/promises';
import debug from 'debug';

import { WARP_FWMARK } from './WarpInterface';
import type { InterfaceType } from '#db/repositories/interface/types';
import type { ObfuscatorPresetType } from '#db/repositories/obfuscatorPreset/types';
import { WIREGUARD_PORT_MIN } from '#db/repositories/obfuscatorPreset/types';
import {
  effectiveObfuscateBytes,
  effectiveSourceIf,
} from '#shared/utils/obfuscation';

const OBFUSCATOR_DEBUG = debug('Obfuscator');

const BINARY = '/usr/local/bin/wg-obfuscator';
const STATS_DIR = '/run/wg-obfuscator';
const PLACEHOLDER_KEY = 'changeme';
const BINARY_DIR = BINARY.slice(0, BINARY.lastIndexOf('/') + 1);
const BINARY_BASE = BINARY.slice(BINARY.lastIndexOf('/') + 1);
const PGREP_PATTERN = `${BINARY_DIR}[${BINARY_BASE[0]}]${BINARY_BASE.slice(1)}`;
const KEY_LENGTH_MIN = 200;
const KEY_LENGTH_MAX = 254;

function isPrivateIp(ip: string): boolean {
  return /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|127\.|169\.254\.)/.test(
    ip
  );
}

function randomKeyLength(): number {
  const span = KEY_LENGTH_MAX - KEY_LENGTH_MIN + 1;
  return KEY_LENGTH_MIN + (randomBytes(1)[0]! % span);
}

export function generateObfuscatorKey(
  length: number = randomKeyLength()
): string {
  if (length < 1 || length > 255) {
    throw new Error('Key length must be 1..255');
  }
  return randomBytes(length * 2)
    .toString('base64')
    .replace(/[+/=]/g, '')
    .slice(0, length);
}

const SOCKS5_CRED_CHARS =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

export function generateSocks5Credential(length = 5): string {
  const bytes = randomBytes(length);
  let out = '';
  for (let i = 0; i < length; i++) {
    out += SOCKS5_CRED_CHARS[bytes[i]! % SOCKS5_CRED_CHARS.length];
  }
  return out;
}

type RunningPreset = { child: ChildProcess; fingerprint: string };

export type Socks5ClientStats = {
  upBytes: number;
  downBytes: number;
  conns: number;
  idleMs: number;
};

class ObfuscatorService {
  #processes = new Map<number, RunningPreset>();
  #applyLock: Promise<void> = Promise.resolve();
  #reconcileTimer: ReturnType<typeof setTimeout> | null = null;
  #stopping = false;

  serverTarget(preset: ObfuscatorPresetType, wgPort: number): string {
    return preset.target?.trim() || `127.0.0.1:${wgPort}`;
  }

  #statsPath(presetId: number): string {
    return `${STATS_DIR}/socks5-${presetId}.stats`;
  }

  async readSocks5Stats(): Promise<Map<string, Socks5ClientStats>> {
    const stats = new Map<string, Socks5ClientStats>();
    const files = await fs.readdir(STATS_DIR).catch(() => [] as string[]);
    await Promise.all(
      files
        .filter((file) => file.endsWith('.stats'))
        .map(async (file) => {
          const content = await fs
            .readFile(`${STATS_DIR}/${file}`, 'utf8')
            .catch(() => '');
          for (const line of content.split('\n')) {
            const [login, up, down, conns, idle] = line.split(' ');
            if (!login || idle === undefined) continue;
            stats.set(login, {
              upBytes: Number(up),
              downBytes: Number(down),
              conns: Number(conns),
              idleMs: Number(idle),
            });
          }
        })
    );
    return stats;
  }

  buildArgs(
    preset: ObfuscatorPresetType,
    wgPort: number,
    socks5Users: string
  ): string[] {
    const sourceIf = effectiveSourceIf(preset);
    if (preset.mode === 'SOCKS5') {
      const args = [
        '--mode=socks5',
        '--role=server',
        `--source-lport=${preset.extPort}`,
        `--key=${preset.key}`,
        `--masking=${preset.masking}`,
        `--verbose=${preset.verbose}`,
        `--fwmark=${WARP_FWMARK}`,
        `--socks5-stats=${this.#statsPath(preset.id)}`,
      ];
      if (sourceIf) {
        args.push(`--source-if=${sourceIf}`);
      }
      if (preset.masking === 'MEDIA' && preset.mediaSsrc != null) {
        args.push(`--media-ssrc=${preset.mediaSsrc}`);
      }
      if (socks5Users) {
        args.push(`--socks5-users=${socks5Users}`);
      }
      return args;
    }
    return [
      `--source-if=${sourceIf}`,
      `--source-lport=${preset.extPort}`,
      `--target=${this.serverTarget(preset, wgPort)}`,
      `--key=${preset.key}`,
      `--masking=${preset.masking}`,
      `--obfuscate-bytes=${effectiveObfuscateBytes(preset)}`,
      `--max-dummy=${preset.dummy}`,
      `--verbose=${preset.verbose}`,
    ];
  }

  fingerprint(
    preset: ObfuscatorPresetType,
    wgPort: number,
    socks5Users: string
  ): string {
    if (preset.mode === 'SOCKS5') {
      return [
        'SOCKS5',
        effectiveSourceIf(preset),
        preset.extPort,
        preset.key,
        preset.masking,
        preset.verbose,
        preset.mediaSsrc ?? '',
        socks5Users,
      ].join('|');
    }
    return [
      preset.extPort,
      effectiveSourceIf(preset),
      this.serverTarget(preset, wgPort),
      preset.key,
      preset.masking,
      effectiveObfuscateBytes(preset),
      preset.dummy,
      preset.verbose,
      wgPort,
    ].join('|');
  }

  spawnPreset(
    preset: ObfuscatorPresetType,
    wgPort: number,
    socks5Users: string
  ): void {
    const args = this.buildArgs(preset, wgPort, socks5Users);
    const child = spawn(BINARY, args, { stdio: 'inherit' });
    const fingerprint = this.fingerprint(preset, wgPort, socks5Users);
    this.#processes.set(preset.id, { child, fingerprint });

    OBFUSCATOR_DEBUG(
      `spawned preset ${preset.id} (${preset.name}) pid=${child.pid} port=${preset.extPort}`
    );

    child.on('exit', (code, signal) => {
      const current = this.#processes.get(preset.id);
      if (current?.child === child) {
        OBFUSCATOR_DEBUG(
          `preset ${preset.id} exited unexpectedly: code=${code} signal=${signal}; scheduling respawn`
        );
        this.#processes.delete(preset.id);
        this.#scheduleReconcile();
      }
    });

    child.on('error', (err) => {
      OBFUSCATOR_DEBUG(
        `preset ${preset.id} spawn error: ${(err as Error).message}`
      );
    });
  }

  async killPreset(presetId: number): Promise<void> {
    const entry = this.#processes.get(presetId);
    if (!entry) return;
    this.#processes.delete(presetId);
    await fs.rm(this.#statsPath(presetId), { force: true }).catch(() => {});

    const { child } = entry;
    if (child.exitCode !== null || child.signalCode !== null) {
      OBFUSCATOR_DEBUG(`preset ${presetId} pid=${child.pid} already exited`);
      return;
    }

    await new Promise<void>((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) return;
        settled = true;
        clearTimeout(sigkillTimer);
        clearTimeout(guardTimer);
        resolve();
      };

      child.once('exit', finish);

      const sigkillTimer = setTimeout(() => {
        try {
          child.kill('SIGKILL');
        } catch {
          // ignore
        }
      }, 2000);
      const guardTimer = setTimeout(finish, 5000);

      try {
        child.kill('SIGTERM');
      } catch {
        finish();
      }
    });

    OBFUSCATOR_DEBUG(`killed preset ${presetId} pid=${child.pid}`);
  }

  async #waitForNoBinary(timeoutMs = 5000): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    let escalated = false;
    while (Date.now() < deadline) {
      const running = await exec(`pgrep -f '${PGREP_PATTERN}' || true`).catch(
        () => ''
      );
      if (!running.trim()) return;
      if (!escalated && Date.now() > deadline - timeoutMs / 2) {
        await exec(`pkill -9 -f '${PGREP_PATTERN}' || true`).catch(() => {});
        escalated = true;
      }
      await new Promise((r) => setTimeout(r, 150));
    }
  }

  #scheduleReconcile(delayMs = 2000): void {
    if (this.#stopping || this.#reconcileTimer) return;
    this.#reconcileTimer = setTimeout(() => {
      this.#reconcileTimer = null;
      this.applyAll().catch((err) =>
        OBFUSCATOR_DEBUG(`reconcile failed: ${(err as Error).message}`)
      );
    }, delayMs);
    this.#reconcileTimer.unref();
  }

  applyAll(): Promise<void> {
    const run = () => this.#applyAllInner();
    this.#applyLock = this.#applyLock.then(run, run);
    return this.#applyLock;
  }

  async #applyAllInner(): Promise<void> {
    const presets = await Database.obfuscatorPresets.list();
    const iface = await Database.interfaces.get();
    const socks5Members = await Database.clients.getSocks5PresetMembers();

    const usersByPreset = new Map<number, string>();
    for (const preset of presets) {
      if (preset.mode !== 'SOCKS5') continue;
      const members = socks5Members
        .filter((m) => m.presetId === preset.id)
        .map((m) => `${m.socks5Login}:${m.socks5Password}`)
        .sort();
      usersByPreset.set(preset.id, members.join(','));
    }

    const desired = new Map(presets.map((p) => [p.id, p]));

    for (const id of [...this.#processes.keys()]) {
      if (!desired.has(id)) await this.killPreset(id);
    }

    for (const preset of presets) {
      const socks5Users = usersByPreset.get(preset.id) ?? '';
      const current = this.#processes.get(preset.id);
      const want = this.fingerprint(preset, iface.port, socks5Users);
      if (current && current.fingerprint === want) continue;
      if (current) await this.killPreset(preset.id);
      this.spawnPreset(preset, iface.port, socks5Users);
    }

    OBFUSCATOR_DEBUG(
      `applied ${presets.length} presets, ${this.#processes.size} processes running`
    );
  }

  async Shutdown(): Promise<void> {
    OBFUSCATOR_DEBUG('Shutting down obfuscator presets');
    this.#stopping = true;
    if (this.#reconcileTimer) {
      clearTimeout(this.#reconcileTimer);
      this.#reconcileTimer = null;
    }
    for (const id of [...this.#processes.keys()]) await this.killPreset(id);
    await exec(`pkill -f '${PGREP_PATTERN}' || true`).catch(() => {});
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

    const pub = await exec('curl -sf --max-time 5 https://api.ipify.org').catch(
      () => ''
    );
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

  buildClientObfConf(
    preset: ObfuscatorPresetType,
    iface: InterfaceType
  ): string {
    return [
      '[instance]',
      'source-if = 127.0.0.1',
      `source-lport = ${preset.clientWgLocalPort}`,
      `target = ${iface.serverPublicDomain || iface.serverPublicIpV4}:${preset.extPort}`,
      `key = ${preset.key}`,
      `masking = ${preset.masking}`,
      `obfuscate-bytes = ${effectiveObfuscateBytes(preset)}`,
      `max-dummy = ${preset.dummy}`,
      `verbose = ${preset.verbose}`,
      '',
    ].join('\n');
  }

  buildSocks5ClientObfConf(
    preset: ObfuscatorPresetType,
    iface: InterfaceType
  ): string {
    const lines = [
      '[instance]',
      'mode = socks5',
      'role = client',
      'source-if = 127.0.0.1',
      `source-lport = ${preset.clientLocalPort}`,
      `target = ${iface.serverPublicDomain || iface.serverPublicIpV4}:${preset.extPort}`,
      `key = ${preset.key}`,
      `masking = ${preset.masking}`,
      `verbose = ${preset.verbose}`,
    ];
    if (preset.masking === 'MEDIA' && preset.mediaSsrc != null) {
      lines.push(`media-ssrc = ${preset.mediaSsrc}`);
    }
    lines.push('');
    return lines.join('\n');
  }

  buildSocks5CredentialsSection(login: string, password: string): string {
    return ['[socks5]', `login = ${login}`, `password = ${password}`, ''].join(
      '\n'
    );
  }

  async #rotatePlaceholderKeys(): Promise<void> {
    const presets = await Database.obfuscatorPresets.list();
    const placeholders = presets.filter((p) => p.key === PLACEHOLDER_KEY);
    if (placeholders.length === 0) return;

    const clients = await Database.clients.getAll();
    if (clients.length > 0) {
      OBFUSCATOR_DEBUG(
        `placeholder key present but ${clients.length} client(s) exist; leaving key unchanged to avoid breaking deployed configs`
      );
      return;
    }

    for (const preset of placeholders) {
      await Database.obfuscatorPresets.regenerateKey(preset.id);
      OBFUSCATOR_DEBUG(
        `rotated placeholder obfuscation key for preset ${preset.id} (${preset.name})`
      );
    }
  }

  async Startup(): Promise<void> {
    OBFUSCATOR_DEBUG('Starting Obfuscator...');
    this.#stopping = false;

    await fs.mkdir(STATS_DIR, { recursive: true });
    for (const file of await fs
      .readdir(STATS_DIR)
      .catch(() => [] as string[])) {
      await fs.rm(`${STATS_DIR}/${file}`, { force: true }).catch(() => {});
    }

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
      extPort: WIREGUARD_PORT_MIN,
      sourceIf: '',
      target: null,
      key: generateObfuscatorKey(),
      masking: 'MEDIA',
      obfuscateBytes: 0,
      dummy: 40,
      verbose: 'error',
      clientWgLocalPort: 13255,
    });

    await this.#rotatePlaceholderKeys();

    await exec(`pkill -f '${PGREP_PATTERN}' || true`).catch(() => {});
    await this.#waitForNoBinary();

    await this.applyAll();

    OBFUSCATOR_DEBUG('Obfuscator started');
  }
}

export const Obfuscator = new ObfuscatorService();

export default Obfuscator;
