import fs from 'node:fs/promises';
import debug from 'debug';

import { warpApi } from '../phobos/warp/client';
import type { WarpManualType, WarpType } from '#db/repositories/warp/types';

const WARP_DEBUG = debug('Warp');

const WARP_INTERFACE = 'warp0';
const WARP_TABLE = 200;
export const WARP_FWMARK = 9224;
const WARP_CONFIG_PATH = `/etc/wireguard/${WARP_INTERFACE}.conf`;
const HANDSHAKE_RETRIES = 10;
const HANDSHAKE_DELAY_MS = 1000;
const WARP_ONLINE_FLOOR_S = 135;
const CONNECTIVITY_TIMEOUT_S = 5;
const CONNECTIVITY_PROBE_URL = 'http://cp.cloudflare.com/generate_204';

function joinShell(parts: string[]): string {
  return parts
    .map((p) => p.trim())
    .filter(Boolean)
    .map((p) => (p.endsWith(';') ? p : `${p};`))
    .join(' ');
}

class WarpInterfaceService {
  buildConfig(
    warp: WarpType,
    ipv4Cidr: string,
    ipv6Cidr: string,
    enableIpv6: boolean
  ): string {
    const address =
      `${warp.addressV4}/32` +
      (enableIpv6 && warp.addressV6 ? `, ${warp.addressV6}/128` : '');

    const postUp = joinShell([
      `ip route replace ${ipv4Cidr} dev wg0 table ${WARP_TABLE}`,
      `ip rule del from ${ipv4Cidr} lookup ${WARP_TABLE} 2>/dev/null || true`,
      `ip rule add from ${ipv4Cidr} lookup ${WARP_TABLE}`,
      `iptables -t nat -A POSTROUTING -s ${ipv4Cidr} -o %i -j MASQUERADE`,
      `ip rule del fwmark ${WARP_FWMARK} lookup ${WARP_TABLE} 2>/dev/null || true`,
      `ip rule add fwmark ${WARP_FWMARK} lookup ${WARP_TABLE}`,
      `iptables -t nat -A POSTROUTING -m mark --mark ${WARP_FWMARK} -o %i -j MASQUERADE`,
      ...(enableIpv6
        ? [
            `ip -6 route replace ${ipv6Cidr} dev wg0 table ${WARP_TABLE}`,
            `ip -6 rule del from ${ipv6Cidr} lookup ${WARP_TABLE} 2>/dev/null || true`,
            `ip -6 rule add from ${ipv6Cidr} lookup ${WARP_TABLE}`,
            `ip6tables -t nat -A POSTROUTING -s ${ipv6Cidr} -o %i -j MASQUERADE`,
            `ip -6 rule del fwmark ${WARP_FWMARK} lookup ${WARP_TABLE} 2>/dev/null || true`,
            `ip -6 rule add fwmark ${WARP_FWMARK} lookup ${WARP_TABLE}`,
            `ip6tables -t nat -A POSTROUTING -m mark --mark ${WARP_FWMARK} -o %i -j MASQUERADE`,
          ]
        : []),
    ]);

    const postDown = joinShell([
      `ip rule del from ${ipv4Cidr} lookup ${WARP_TABLE} 2>/dev/null || true`,
      `iptables -t nat -D POSTROUTING -s ${ipv4Cidr} -o %i -j MASQUERADE 2>/dev/null || true`,
      `ip rule del fwmark ${WARP_FWMARK} lookup ${WARP_TABLE} 2>/dev/null || true`,
      `iptables -t nat -D POSTROUTING -m mark --mark ${WARP_FWMARK} -o %i -j MASQUERADE 2>/dev/null || true`,
      ...(enableIpv6
        ? [
            `ip -6 rule del from ${ipv6Cidr} lookup ${WARP_TABLE} 2>/dev/null || true`,
            `ip6tables -t nat -D POSTROUTING -s ${ipv6Cidr} -o %i -j MASQUERADE 2>/dev/null || true`,
            `ip -6 rule del fwmark ${WARP_FWMARK} lookup ${WARP_TABLE} 2>/dev/null || true`,
            `ip6tables -t nat -D POSTROUTING -m mark --mark ${WARP_FWMARK} -o %i -j MASQUERADE 2>/dev/null || true`,
          ]
        : []),
    ]);

    const ifaceLines = [
      `PrivateKey = ${warp.privateKey}`,
      `Address = ${address}`,
      `MTU = ${warp.mtu}`,
      `Table = ${WARP_TABLE}`,
      `PostUp = ${postUp}`,
      `PostDown = ${postDown}`,
    ];

    const peerLines = [
      `PublicKey = ${warp.peerPublicKey}`,
      ...(warp.presharedKey ? [`PresharedKey = ${warp.presharedKey}`] : []),
      `Endpoint = ${warp.endpoint}`,
      `AllowedIPs = 0.0.0.0/0${enableIpv6 ? ', ::/0' : ''}`,
      `PersistentKeepalive = ${warp.persistentKeepalive}`,
    ];

    return `[Interface]\n${ifaceLines.join('\n')}\n\n[Peer]\n${peerLines.join('\n')}\n`;
  }

  buildUserConfig(warp: WarpType, enableIpv6: boolean): string {
    const address =
      `${warp.addressV4}/32` +
      (enableIpv6 && warp.addressV6 ? `, ${warp.addressV6}/128` : '');

    const ifaceLines = [
      `PrivateKey = ${warp.privateKey}`,
      `Address = ${address}`,
      `MTU = ${warp.mtu}`,
      ...(warp.dns ? [`DNS = ${warp.dns}`] : []),
    ];

    const peerLines = [
      `PublicKey = ${warp.peerPublicKey}`,
      ...(warp.presharedKey ? [`PresharedKey = ${warp.presharedKey}`] : []),
      `Endpoint = ${warp.endpoint}`,
      `AllowedIPs = 0.0.0.0/0${enableIpv6 ? ', ::/0' : ''}`,
      `PersistentKeepalive = ${warp.persistentKeepalive}`,
    ];

    return `[Interface]\n${ifaceLines.join('\n')}\n\n[Peer]\n${peerLines.join('\n')}\n`;
  }

  async #writeConfig() {
    const [warp, wgInterface] = await Promise.all([
      Database.warp.get(),
      Database.interfaces.get(),
    ]);

    const config = this.buildConfig(
      warp,
      wgInterface.ipv4Cidr,
      wgInterface.ipv6Cidr,
      !WG_ENV.DISABLE_IPV6
    );

    await fs.writeFile(WARP_CONFIG_PATH, config, { mode: 0o600 });
  }

  async #up() {
    await exec(`wg-quick up ${WARP_INTERFACE}`);
  }

  async #down() {
    await exec(`wg-quick down ${WARP_INTERFACE}`).catch(() => {});
  }

  async #latestHandshakeTs(): Promise<number> {
    const out = await exec(`wg show ${WARP_INTERFACE} latest-handshakes`, {
      log: false,
    }).catch(() => '');

    return out
      .trim()
      .split('\n')
      .filter(Boolean)
      .reduce((max, line) => {
        const ts = Number.parseInt(line.split('\t')[1] ?? '0', 10);
        return ts > max ? ts : max;
      }, 0);
  }

  async #handshakeEstablished(): Promise<boolean> {
    return (await this.#latestHandshakeTs()) > 0;
  }

  async status(): Promise<{ online: boolean; lastHandshakeAt: string | null }> {
    const wgInterface = await Database.interfaces.get();
    if (wgInterface.egressMode !== 'warp' || !wgInterface.enabled) {
      return { online: false, lastHandshakeAt: null };
    }

    const ts = await this.#latestHandshakeTs();
    if (ts <= 0) {
      return { online: false, lastHandshakeAt: null };
    }

    const warp = await Database.warp.get();
    const stalenessMs =
      Math.max(warp.persistentKeepalive * 3, WARP_ONLINE_FLOOR_S) * 1000;
    const ageMs = Date.now() - ts * 1000;

    return {
      online: ageMs < stalenessMs,
      lastHandshakeAt: new Date(ts * 1000).toISOString(),
    };
  }

  async connectivityCheck(): Promise<boolean> {
    const code = await exec(
      `curl --interface ${WARP_INTERFACE} -s -o /dev/null -w '%{http_code}' --max-time ${CONNECTIVITY_TIMEOUT_S} ${CONNECTIVITY_PROBE_URL}`,
      { log: false }
    ).catch(() => '');

    return code.trim() === '204' || code.trim() === '200';
  }

  async #healthCheck(): Promise<boolean> {
    for (let attempt = 0; attempt < HANDSHAKE_RETRIES; attempt += 1) {
      if (await this.#handshakeEstablished()) {
        return true;
      }
      await new Promise((resolve) => setTimeout(resolve, HANDSHAKE_DELAY_MS));
    }
    return false;
  }

  /**
   * Brings warp0 up with a health check. On failure, tears it down and resets
   * egressMode to 'wan' so clients keep WAN connectivity.
   * @throws when the tunnel cannot be established
   */
  async enable() {
    if (!(await Database.warp.isRegistered())) {
      throw new Error('WARP is not registered');
    }

    await this.#down();
    await this.#writeConfig();
    await this.#up();

    const healthy = await this.#healthCheck();
    if (!healthy) {
      await this.#down();
      await Database.interfaces.update({ egressMode: 'wan' });
      throw new Error(
        'WARP tunnel did not establish: endpoint UDP 2408 may be blocked by your provider'
      );
    }

    WARP_DEBUG('WARP interface is up and healthy');
  }

  async disable() {
    await this.#down();
    WARP_DEBUG('WARP interface is down');
  }

  /** Re-applies the interface only when WARP egress is currently active. */
  async reapply() {
    const wgInterface = await Database.interfaces.get();
    if (wgInterface.egressMode === 'warp' && wgInterface.enabled) {
      await this.enable();
    }
  }

  async register(): Promise<void> {
    const privateKey = await wg.generatePrivateKey();
    const publicKey = await wg.getPublicKey(privateKey);
    const registration = await warpApi.register(privateKey, publicKey);
    await Database.warp.setRegistration(registration);
    await this.reapply();
  }

  async changeIp(): Promise<void> {
    const previous = await Database.warp.get();
    await this.register();
    if (previous.licenseKey.length >= 26) {
      await this.setLicense(previous.licenseKey).catch((err) => {
        WARP_DEBUG('Failed to re-apply WARP license after IP change:', err);
      });
    }
    await Database.warp.setLastUpdateAt(new Date().toISOString());
  }

  async setLicense(license: string): Promise<void> {
    const warp = await Database.warp.get();
    await warpApi.setLicense(warp.deviceId, warp.accessToken, license);
    await Database.warp.setLicenseKey(license);
  }

  async remoteConfig(): Promise<unknown> {
    const warp = await Database.warp.get();
    return warpApi.getConfig(warp.deviceId, warp.accessToken);
  }

  async delete(): Promise<void> {
    await this.disable();
    await Database.warp.clear();
    await Database.interfaces.update({ egressMode: 'wan' });
    await fs.rm(WARP_CONFIG_PATH, { force: true });
  }

  async importConfig(data: WarpManualType): Promise<void> {
    const [warpRow, wgInterface] = await Promise.all([
      Database.warp.get(),
      Database.interfaces.get(),
    ]);

    const wasActive = wgInterface.egressMode === 'warp' && wgInterface.enabled;

    const enableIpv6 = !WG_ENV.DISABLE_IPV6;
    const testConfig = this.buildConfig(
      { ...warpRow, ...data },
      wgInterface.ipv4Cidr,
      wgInterface.ipv6Cidr,
      enableIpv6
    );

    await this.#down();
    await fs.writeFile(WARP_CONFIG_PATH, testConfig, { mode: 0o600 });
    await this.#up();

    const healthy = await this.#healthCheck();
    if (!healthy) {
      await this.#down();
      if (wasActive) {
        await this.#writeConfig().catch(() => {});
        await this.#up().catch(() => {});
      }
      throw new Error(
        'WARP handshake failed: endpoint may be unreachable or blocked'
      );
    }

    await Database.warp.update(data);
    WARP_DEBUG('WARP config imported and interface is up');
  }

  async Startup() {
    const wgInterface = await Database.interfaces.get();
    if (
      wgInterface.egressMode !== 'warp' ||
      !wgInterface.enabled ||
      !(await Database.warp.isRegistered())
    ) {
      return;
    }

    WARP_DEBUG('Restoring WARP egress on startup...');
    await this.enable().catch((err) => {
      console.warn(`WARNING: failed to restore WARP egress: ${err.message}`);
    });
  }

  async Shutdown() {
    await this.#down();
  }
}

export const WarpInterface = new WarpInterfaceService();

export default WarpInterface;
