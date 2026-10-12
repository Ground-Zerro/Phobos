import { isIPv6 } from 'is-ip';
import { createLogger } from './logger';

import { execFile } from './cmd';
import type { ClientType } from '#db/repositories/client/types';
import type { InterfaceType } from '#db/repositories/interface/types';
import type { UserConfigType } from '#db/repositories/userConfig/types';

const FW_DEBUG = createLogger('Firewall');
const CHAIN_NAME = 'WG_CLIENTS';
const DROP_RULE = `-A ${CHAIN_NAME} -j DROP`;

type ParsedEntry = {
  ip: string;
  port?: number;
  proto?: 'tcp' | 'udp' | 'both';
};

type FirewallClient = Pick<
  ClientType,
  | 'id'
  | 'name'
  | 'ipv4Address'
  | 'ipv6Address'
  | 'allowedIps'
  | 'firewallIps'
  | 'enabled'
>;

type FirewallState = {
  wgInterface: InterfaceType;
  clients: FirewallClient[];
  userConfig: UserConfigType;
  enableIpv6: boolean;
};

type FamilyRules = { v4: string[]; v6: string[] };

const FAMILIES = [
  { key: 'v4', iptables: 'iptables', restore: 'iptables-restore' },
  { key: 'v6', iptables: 'ip6tables', restore: 'ip6tables-restore' },
] as const;

function sanitizeComment(clientId: number, clientName: string): string {
  const safe = clientName.replace(/[^a-zA-Z0-9 _.-]/g, '');
  const comment = `client ${clientId}: ${safe}`;
  return comment.slice(0, 256);
}

export function parseFirewallEntry(entry: string): ParsedEntry {
  let proto: 'tcp' | 'udp' | 'both' | undefined;
  let remaining = entry;

  if (entry.endsWith('/tcp')) {
    proto = 'tcp';
    remaining = entry.slice(0, -4);
  } else if (entry.endsWith('/udp')) {
    proto = 'udp';
    remaining = entry.slice(0, -4);
  }

  if (remaining.startsWith('[')) {
    const match = remaining.match(/^\[(.+)\]:(\d+)$/);
    if (match && match[1] && match[2]) {
      return {
        ip: match[1],
        port: parseInt(match[2], 10),
        proto: proto ?? 'both',
      };
    }
    const ipMatch = remaining.match(/^\[(.+)\]$/);
    if (ipMatch && ipMatch[1]) {
      if (proto) {
        throw new Error(
          `Invalid firewall entry "${entry}": Protocol (/${proto}) requires a port. Use format like "[${ipMatch[1]}]:443/${proto}"`
        );
      }
      return { ip: ipMatch[1] };
    }
    if (proto) {
      throw new Error(
        `Invalid firewall entry "${entry}": Protocol (/${proto}) requires a port`
      );
    }
    return { ip: remaining };
  }

  const colonCount = (remaining.match(/:/g) || []).length;

  if (colonCount === 1) {
    const lastColon = remaining.lastIndexOf(':');
    const possiblePort = remaining.slice(lastColon + 1);
    if (/^\d+$/.test(possiblePort)) {
      return {
        ip: remaining.slice(0, lastColon),
        port: parseInt(possiblePort, 10),
        proto: proto ?? 'both',
      };
    }
  }

  if (proto) {
    throw new Error(
      `Invalid firewall entry "${entry}": Protocol (/${proto}) requires a port. Use format like "${remaining}:443/${proto}"`
    );
  }
  return { ip: remaining };
}

function generateRuleArgs(
  clientIp: string,
  entry: ParsedEntry,
  comment?: string
): string[] {
  const rules: string[] = [];
  const commentArg = comment ? ` -m comment --comment "${comment}"` : '';
  const baseArgs = `-A ${CHAIN_NAME} -s ${clientIp} -d ${entry.ip}`;

  if (entry.port) {
    if (entry.proto === 'tcp' || entry.proto === 'both') {
      rules.push(
        `${baseArgs} -p tcp --dport ${entry.port}${commentArg} -j ACCEPT`
      );
    }
    if (entry.proto === 'udp' || entry.proto === 'both') {
      rules.push(
        `${baseArgs} -p udp --dport ${entry.port}${commentArg} -j ACCEPT`
      );
    }
  } else {
    rules.push(`${baseArgs}${commentArg} -j ACCEPT`);
  }

  return rules;
}

function collectRules(
  clients: FirewallClient[],
  defaultAllowedIps: string[],
  enableIpv6: boolean
): FamilyRules {
  const rules: FamilyRules = { v4: [], v6: [] };

  for (const client of clients) {
    if (!client.enabled) continue;

    const effectiveIps =
      client.firewallIps && client.firewallIps.length > 0
        ? client.firewallIps
        : (client.allowedIps ?? defaultAllowedIps);
    const comment = sanitizeComment(client.id, client.name);

    for (const ipEntry of effectiveIps) {
      const parsed = parseFirewallEntry(ipEntry);
      const baseIp = parsed.ip.split('/')[0] ?? parsed.ip;

      if (!isIPv6(baseIp)) {
        rules.v4.push(...generateRuleArgs(client.ipv4Address, parsed, comment));
      } else if (enableIpv6) {
        rules.v6.push(...generateRuleArgs(client.ipv6Address, parsed, comment));
      }
    }
  }

  rules.v4.push(DROP_RULE);
  if (enableIpv6) {
    rules.v6.push(DROP_RULE);
  }

  return rules;
}

function buildRestorePayload(rules: readonly string[]): string {
  return ['*filter', `:${CHAIN_NAME} - [0:0]`, ...rules, 'COMMIT', ''].join(
    '\n'
  );
}

function ignoreFailure(promise: Promise<string>): Promise<void> {
  return promise.then(
    () => undefined,
    () => undefined
  );
}

class FirewallService {
  #tail: Promise<void> = Promise.resolve();
  #queued: { state: FirewallState } | null = null;
  #queuedDone: Promise<void> | null = null;
  #available: boolean | null = null;

  rebuildRules(
    wgInterface: InterfaceType,
    clients: FirewallClient[],
    userConfig: UserConfigType,
    enableIpv6: boolean
  ): Promise<void> {
    const state = { wgInterface, clients, userConfig, enableIpv6 };

    if (this.#queued && this.#queuedDone) {
      FW_DEBUG('Rebuild already queued, replacing its state');
      this.#queued.state = state;
      return this.#queuedDone;
    }

    const slot = { state };
    this.#queued = slot;
    const done = this.#tail.then(() => {
      this.#queued = null;
      this.#queuedDone = null;
      return this.#apply(slot.state);
    });
    this.#queuedDone = done;
    this.#tail = done.catch(() => undefined);
    return done;
  }

  async #apply({
    wgInterface,
    clients,
    userConfig,
    enableIpv6,
  }: FirewallState): Promise<void> {
    if (!wgInterface.firewallEnabled) {
      FW_DEBUG('Firewall filtering disabled, removing any existing rules');
      await this.#removeFiltering(wgInterface.name);
      return;
    }

    const rules = collectRules(
      clients,
      userConfig.defaultAllowedIps,
      enableIpv6
    );

    for (const family of FAMILIES) {
      await execFile(family.restore, ['--noflush'], {
        input: buildRestorePayload(rules[family.key]),
      });
      await this.#ensureJump(family.iptables, wgInterface.name);
    }

    FW_DEBUG(
      `Firewall rules applied: ${rules.v4.length} IPv4, ${rules.v6.length} IPv6`
    );
  }

  async #ensureJump(iptables: string, interfaceName: string): Promise<void> {
    const jump = ['FORWARD', '-i', interfaceName, '-j', CHAIN_NAME];
    try {
      await execFile(iptables, ['-C', ...jump], { log: false });
    } catch {
      await execFile(iptables, ['-I', 'FORWARD', '1', ...jump.slice(1)]);
    }
  }

  async #removeFiltering(interfaceName: string): Promise<void> {
    for (const { iptables } of FAMILIES) {
      await ignoreFailure(
        execFile(iptables, [
          '-D',
          'FORWARD',
          '-i',
          interfaceName,
          '-j',
          CHAIN_NAME,
        ])
      );
      await ignoreFailure(execFile(iptables, ['-F', CHAIN_NAME]));
      await ignoreFailure(execFile(iptables, ['-X', CHAIN_NAME]));
    }
  }

  async isAvailable(): Promise<boolean> {
    if (this.#available !== null) {
      return this.#available;
    }

    try {
      await execFile('iptables', ['--version']);
      if (!WG_ENV.DISABLE_IPV6) {
        await execFile('ip6tables', ['--version']);
      }
      this.#available = true;
    } catch (error) {
      FW_DEBUG('iptables/ip6tables is not available:', error);
      this.#available = false;
    }
    return this.#available;
  }

  clearAvailabilityCache(): void {
    this.#available = null;
  }
}

export const firewall = new FirewallService();

export const firewallTestExports = {
  parseFirewallEntry,
  generateRuleArgs,
  sanitizeComment,
  collectRules,
  buildRestorePayload,
};
