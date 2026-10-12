import { readdir, readFile } from 'node:fs/promises';

import { execFile } from './cmd';

const SNAPSHOT_TTL_MS = 500;

export const SOCKS5_STATS_DIR = '/run/wg-obfuscator';

export function socks5StatsPath(presetId: number): string {
  return `${SOCKS5_STATS_DIR}/socks5-${presetId}.stats`;
}

export type PeerRuntime = {
  endpoint: string | null;
  latestHandshakeAt: Date | null;
  transferRx: number;
  transferTx: number;
};

export type Socks5ClientStats = {
  upBytes: number;
  downBytes: number;
  conns: number;
  idleMs: number;
};

export type RuntimeSnapshot = {
  peers: ReadonlyMap<string, PeerRuntime>;
  socks5: ReadonlyMap<string, Socks5ClientStats>;
};

function parseWgDump(raw: string): Map<string, PeerRuntime> {
  const peers = new Map<string, PeerRuntime>();
  const lines = raw.split('\n');
  for (let i = 1; i < lines.length; i++) {
    const fields = lines[i]!.split('\t');
    if (fields.length < 7) continue;
    const handshake = fields[4]!;
    peers.set(fields[0]!, {
      endpoint: fields[2] === '(none)' ? null : fields[2]!,
      latestHandshakeAt:
        handshake === '0' ? null : new Date(Number(handshake) * 1000),
      transferRx: Number(fields[5]),
      transferTx: Number(fields[6]),
    });
  }
  return peers;
}

async function readPeers(interfaceName: string) {
  const raw = await execFile('wg', ['show', interfaceName, 'dump'], {
    log: false,
  });
  return parseWgDump(raw);
}

async function readSocks5Stats(): Promise<Map<string, Socks5ClientStats>> {
  const stats = new Map<string, Socks5ClientStats>();
  const files = await readdir(SOCKS5_STATS_DIR).catch(() => [] as string[]);
  const contents = await Promise.all(
    files
      .filter((file) => file.endsWith('.stats'))
      .map((file) =>
        readFile(`${SOCKS5_STATS_DIR}/${file}`, 'utf8').catch(() => '')
      )
  );
  for (const content of contents) {
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
  }
  return stats;
}

class RuntimeStatsService {
  #snapshot: RuntimeSnapshot | null = null;
  #takenAt = 0;
  #pending: Promise<RuntimeSnapshot> | null = null;

  get(interfaceName: string): Promise<RuntimeSnapshot> {
    if (this.#snapshot && Date.now() - this.#takenAt < SNAPSHOT_TTL_MS) {
      return Promise.resolve(this.#snapshot);
    }
    this.#pending ??= this.#take(interfaceName).finally(() => {
      this.#pending = null;
    });
    return this.#pending;
  }

  async #take(interfaceName: string): Promise<RuntimeSnapshot> {
    const [peers, socks5] = await Promise.all([
      readPeers(interfaceName),
      readSocks5Stats(),
    ]);
    this.#snapshot = { peers, socks5 };
    this.#takenAt = Date.now();
    return this.#snapshot;
  }
}

export const RuntimeStats = new RuntimeStatsService();

export const runtimeStatsTestExports = { parseWgDump };
