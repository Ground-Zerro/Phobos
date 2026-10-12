import { spawn, type ChildProcess } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import fs from 'node:fs/promises';
import { isIPv4 } from 'is-ip';
import { createLogger } from './logger';

import { WARP_FWMARK } from './WarpInterface';
import { SOCKS5_STATS_DIR, socks5StatsPath } from './RuntimeStats';
import type { ObfuscatorPresetType } from '#db/repositories/obfuscatorPreset/types';
import { WIREGUARD_PORT_MIN } from '#db/repositories/obfuscatorPreset/types';
import {
  PRESET_DEFAULTS,
  effectiveObfuscateBytes,
  effectiveSourceIf,
} from '#shared/utils/obfuscation';

const OBFUSCATOR_DEBUG = createLogger('Obfuscator');

const BINARY = '/usr/local/bin/wg-obfuscator';
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

type ServerOption = readonly [string, string | number];

function serverOptions(
  preset: ObfuscatorPresetType,
  wgPort: number,
  socks5Users: string
): ServerOption[] {
  const sourceIf = effectiveSourceIf(preset);
  if (preset.mode === 'SOCKS5') {
    const options: ServerOption[] = [
      ['mode', 'socks5'],
      ['role', 'server'],
      ['source-lport', preset.extPort],
      ['key', preset.key],
      ['masking', preset.masking],
      ['verbose', preset.verbose],
      ['fwmark', WARP_FWMARK],
      ['socks5-stats', socks5StatsPath(preset.id)],
    ];
    if (sourceIf) options.push(['source-if', sourceIf]);
    if (preset.masking === 'MEDIA' && preset.mediaSsrc != null) {
      options.push(['media-ssrc', preset.mediaSsrc]);
    }
    if (socks5Users) options.push(['socks5-users', socks5Users]);
    return options;
  }
  return [
    ['source-if', sourceIf],
    ['source-lport', preset.extPort],
    ['target', preset.target?.trim() || `127.0.0.1:${wgPort}`],
    ['key', preset.key],
    ['masking', preset.masking],
    ['obfuscate-bytes', effectiveObfuscateBytes(preset)],
    ['max-dummy', preset.dummy],
    ['verbose', preset.verbose],
  ];
}

function toArgs(options: readonly ServerOption[]): string[] {
  return options.map(([name, value]) => `--${name}=${value}`);
}

async function defaultRouteDevice(): Promise<string | undefined> {
  const route = await exec('ip route');
  return route.match(/^default.+dev\s+(\S+)/m)?.[1];
}

class ObfuscatorService {
  #processes = new Map<number, RunningPreset>();
  #applyLock: Promise<void> = Promise.resolve();
  #reconcileTimer: ReturnType<typeof setTimeout> | null = null;
  #stopping = false;

  #spawnPreset(preset: ObfuscatorPresetType, args: string[]): void {
    const child = spawn(BINARY, args, { stdio: 'inherit' });
    this.#processes.set(preset.id, { child, fingerprint: args.join('\n') });

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
      OBFUSCATOR_DEBUG(`preset ${preset.id} spawn error: ${err.message}`);
    });
  }

  async #killPreset(presetId: number): Promise<void> {
    const entry = this.#processes.get(presetId);
    if (!entry) return;
    this.#processes.delete(presetId);
    await fs.rm(socks5StatsPath(presetId), { force: true }).catch(() => {});

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

      const sigkillTimer = setTimeout(() => child.kill('SIGKILL'), 2000);
      const guardTimer = setTimeout(finish, 5000);

      if (!child.kill('SIGTERM')) {
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

    const membersByPreset = new Map<number, string[]>();
    for (const m of socks5Members) {
      const list = membersByPreset.get(m.presetId) ?? [];
      list.push(`${m.socks5Login}:${m.socks5Password}`);
      membersByPreset.set(m.presetId, list);
    }

    const desired = new Set(presets.map((p) => p.id));
    for (const id of [...this.#processes.keys()]) {
      if (!desired.has(id)) await this.#killPreset(id);
    }

    for (const preset of presets) {
      const socks5Users =
        preset.mode === 'SOCKS5'
          ? (membersByPreset.get(preset.id) ?? []).sort().join(',')
          : '';
      const args = toArgs(serverOptions(preset, iface.port, socks5Users));
      const current = this.#processes.get(preset.id);
      if (current && current.fingerprint === args.join('\n')) continue;
      if (current) await this.#killPreset(preset.id);
      this.#spawnPreset(preset, args);
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
    for (const id of [...this.#processes.keys()]) await this.#killPreset(id);
    await exec(`pkill -f '${PGREP_PATTERN}' || true`).catch(() => {});
  }

  async #detectPublicIpV4(): Promise<string> {
    const envIp = process.env.WG_HOST;
    if (envIp && isIPv4(envIp)) return envIp;

    const device = await defaultRouteDevice();
    if (device) {
      const out = await exec(`ip -4 addr show dev ${device} scope global`);
      const ip = out.match(/inet\s+(\d+\.\d+\.\d+\.\d+)/)?.[1];
      if (ip && !isPrivateIp(ip)) return ip;
    }

    const pub = (
      await exec('curl -sf --max-time 5 https://api.ipify.org').catch(() => '')
    ).trim();
    if (isIPv4(pub)) return pub;

    throw new Error('Cannot detect public IPv4. Set WG_HOST env variable.');
  }

  async #detectPublicIpV6(): Promise<string | null> {
    const device = await defaultRouteDevice().catch(() => undefined);
    if (!device) return null;
    const out = await exec(`ip -6 addr show dev ${device} scope global`).catch(
      () => ''
    );
    return (
      out
        .match(/inet6\s+([0-9a-f:]+)/gi)
        ?.map((l) => l.replace(/^inet6\s+/i, ''))
        .find((addr) => !/^f[cd]/i.test(addr)) ?? null
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

    await fs.mkdir(SOCKS5_STATS_DIR, { recursive: true });
    for (const file of await fs
      .readdir(SOCKS5_STATS_DIR)
      .catch(() => [] as string[])) {
      await fs
        .rm(`${SOCKS5_STATS_DIR}/${file}`, { force: true })
        .catch(() => {});
    }

    const iface = await Database.interfaces.get();

    if (!iface.serverPublicIpV4) {
      const ipv4 = await this.#detectPublicIpV4().catch(() => '');
      const ipv6 = iface.serverPublicIpV6 ?? (await this.#detectPublicIpV6());
      if (ipv4 || ipv6 !== iface.serverPublicIpV6) {
        await Database.interfaces.update({
          serverPublicIpV4: ipv4,
          serverPublicIpV6: ipv6,
        });
      }
    }

    await Database.obfuscatorPresets.ensureDefault({
      ...PRESET_DEFAULTS,
      masking: 'MEDIA',
      extPort: WIREGUARD_PORT_MIN,
      sourceIf: '',
      target: null,
      key: generateObfuscatorKey(),
    });

    await this.#rotatePlaceholderKeys();

    await exec(`pkill -f '${PGREP_PATTERN}' || true`).catch(() => {});
    await this.#waitForNoBinary();

    await this.applyAll();

    OBFUSCATOR_DEBUG('Obfuscator started');
  }
}

export const Obfuscator = new ObfuscatorService();
