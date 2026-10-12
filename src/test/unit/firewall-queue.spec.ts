import { beforeEach, describe, expect, test, vi } from 'vitest';

const calls: { file: string; args: readonly string[]; input?: string }[] = [];
let gate: Promise<void> = Promise.resolve();

vi.mock('../../server/utils/cmd', () => ({
  execFile: vi.fn(
    async (
      file: string,
      args: readonly string[],
      options: { input?: string } = {}
    ) => {
      calls.push({ file, args, input: options.input });
      await gate;
      return '';
    }
  ),
}));

const { firewall } = await import('../../server/utils/firewall');

function state(name: string) {
  return {
    wgInterface: { name: 'wg0', firewallEnabled: true } as never,
    clients: [
      {
        id: 1,
        name,
        ipv4Address: '10.8.0.2',
        ipv6Address: 'fdcc::2',
        allowedIps: ['10.0.0.1'],
        firewallIps: null,
        enabled: true,
      },
    ],
    userConfig: { defaultAllowedIps: [] } as never,
  };
}

function rebuild(name: string) {
  const s = state(name);
  return firewall.rebuildRules(s.wgInterface, s.clients, s.userConfig, true);
}

function appliedNames() {
  return calls
    .filter((c) => c.file === 'iptables-restore')
    .map((c) => c.input?.match(/client 1: (\w+)/)?.[1]);
}

describe('firewall rebuild queue', () => {
  beforeEach(() => {
    calls.length = 0;
    gate = Promise.resolve();
  });

  test('applies with a single restore per family instead of one process per rule', async () => {
    await rebuild('first');
    expect(calls.map((c) => c.file)).toEqual([
      'iptables-restore',
      'iptables',
      'ip6tables-restore',
      'ip6tables',
    ]);
  });

  test('coalesces requests queued during a running rebuild and applies only the latest state', async () => {
    let release!: () => void;
    gate = new Promise((r) => (release = r));

    const running = rebuild('running');
    await Promise.resolve();
    const stale = rebuild('stale');
    const latest = rebuild('latest');

    expect(stale).toBe(latest);

    release();
    await Promise.all([running, stale, latest]);

    expect(appliedNames()).toEqual(['running', 'latest']);
  });

  test('a caller resolves only after its own state has been applied', async () => {
    let release!: () => void;
    gate = new Promise((r) => (release = r));

    const running = rebuild('running');
    await Promise.resolve();
    let queuedApplied = false;
    const queued = rebuild('queued').then(() => {
      queuedApplied = appliedNames().includes('queued');
    });

    release();
    await Promise.all([running, queued]);
    expect(queuedApplied).toBe(true);
  });
});
