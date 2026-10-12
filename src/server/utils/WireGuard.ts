import fs from 'node:fs/promises';
import { createLogger } from './logger';
import type { PeerRuntime, Socks5ClientStats } from './RuntimeStats';
import { buildClientFullConfig } from './clientConfig';
import type { InterfaceType } from '#db/repositories/interface/types';

const WG_DEBUG = createLogger('WireGuard');

function socks5Runtime(
  stats: Socks5ClientStats | undefined,
  now: number
): Omit<PeerRuntime, 'endpoint'> | undefined {
  if (!stats) return undefined;
  return {
    transferRx: stats.upBytes,
    transferTx: stats.downBytes,
    latestHandshakeAt:
      stats.conns > 0
        ? new Date(now)
        : stats.idleMs >= 0
          ? new Date(now - stats.idleMs)
          : null,
  };
}

class WireGuard {
  async saveConfig() {
    const wgInterface = await Database.interfaces.get();
    await this.#saveWireguardConfig(wgInterface);
    await this.#syncWireguardConfig(wgInterface);
    await this.#applyFirewallRules(wgInterface);
  }

  async Restart() {
    const wgInterface = await Database.interfaces.get();
    await wg.down(wgInterface.name).catch(() => {});
    await this.#saveWireguardConfig(wgInterface);
    await wg.up(wgInterface.name);
    await this.#applyFirewallRules(wgInterface);
  }

  async #applyFirewallRules(wgInterface: InterfaceType) {
    const clients = await Database.clients.getAll();
    const userConfig = await Database.userConfigs.get();
    await firewall.rebuildRules(
      wgInterface,
      clients,
      userConfig,
      !WG_ENV.DISABLE_IPV6
    );
  }

  async #saveWireguardConfig(wgInterface: InterfaceType) {
    const clients = await Database.clients.getAll();
    const hooks = await Database.hooks.get();

    const result = [];
    result.push(
      wg.generateServerInterface(wgInterface, hooks, {
        enableIpv6: !WG_ENV.DISABLE_IPV6,
      })
    );

    for (const client of clients) {
      if (!client.enabled) {
        continue;
      }
      result.push(
        wg.generateServerPeer(client, {
          enableIpv6: !WG_ENV.DISABLE_IPV6,
        })
      );
    }

    result.push('');

    WG_DEBUG('Saving Config...');
    await fs.writeFile(
      `/etc/wireguard/${wgInterface.name}.conf`,
      result.join('\n\n'),
      {
        mode: 0o600,
      }
    );
    WG_DEBUG('Config saved successfully.');
  }

  async #syncWireguardConfig(wgInterface: InterfaceType) {
    WG_DEBUG('Syncing Config...');
    await wg.sync(wgInterface.name);
    WG_DEBUG('Config synced successfully.');
  }

  async getClientsForUser(userId: ID, filter?: string) {
    const dbClients = filter?.trim()
      ? await Database.clients.getForUserFiltered(userId, filter)
      : await Database.clients.getForUser(userId);
    return this.#attachRuntimeStats(dbClients);
  }

  async #attachRuntimeStats<
    T extends {
      publicKey: string;
      socks5Login: string | null;
      preset: {
        id: number;
        name: string;
        isDefault: boolean;
        mode: 'WIREGUARD' | 'SOCKS5';
      } | null;
    },
  >(dbClients: T[]) {
    const [wgInterface, defaultPreset] = await Promise.all([
      Database.interfaces.get(),
      Database.obfuscatorPresets.getDefault(),
    ]);
    const defaultPresetInfo = {
      id: defaultPreset.id,
      name: defaultPreset.name,
      isDefault: defaultPreset.isDefault,
      mode: defaultPreset.mode,
    };
    const { peers, socks5 } = await RuntimeStats.get(wgInterface.name);
    const now = Date.now();

    return dbClients.map((client) => {
      const preset = client.preset ?? defaultPresetInfo;
      const peer = peers.get(client.publicKey);
      const runtime =
        preset.mode === 'SOCKS5'
          ? socks5Runtime(
              client.socks5Login ? socks5.get(client.socks5Login) : undefined,
              now
            )
          : peer;
      return Object.assign(client, {
        preset,
        endpoint: peer?.endpoint ?? null,
        latestHandshakeAt: runtime?.latestHandshakeAt ?? null,
        transferRx: runtime?.transferRx ?? null,
        transferTx: runtime?.transferTx ?? null,
      });
    });
  }

  async peerEndpoint(publicKey: string) {
    const wgInterface = await Database.interfaces.get();
    const { peers } = await RuntimeStats.get(wgInterface.name);
    return peers.get(publicKey)?.endpoint ?? null;
  }

  async getAllClients(filter?: string) {
    const dbClients = filter?.trim()
      ? await Database.clients.getAllPublicFiltered(filter)
      : await Database.clients.getAllPublic();
    return this.#attachRuntimeStats(dbClients);
  }

  async getClientFullConfig({ clientId }: { clientId: ID }) {
    const [iface, userConfig, client] = await Promise.all([
      Database.interfaces.get(),
      Database.userConfigs.get(),
      Database.clients.get(clientId),
    ]);
    if (!client) {
      throw new Error('Client not found');
    }

    const preset = await Database.obfuscatorPresets.getForClient(
      client.presetId
    );
    const socks5Credentials =
      preset.mode === 'SOCKS5'
        ? await Database.clients.ensureSocks5Credentials(clientId)
        : null;

    return buildClientFullConfig({
      iface,
      userConfig,
      client,
      preset,
      enableIpv6: !WG_ENV.DISABLE_IPV6,
      socks5Credentials,
    });
  }

  async getClientQRCodeSVG({ clientId }: { clientId: ID }) {
    const config = await this.getClientFullConfig({ clientId });
    return encodeQRCode(config);
  }

  async Startup() {
    WG_DEBUG('Starting WireGuard...');
    let wgInterface = await Database.interfaces.get();

    if (
      wgInterface.privateKey === '---default---' &&
      wgInterface.publicKey === '---default---'
    ) {
      WG_DEBUG('Generating new Wireguard Keys...');
      const privateKey = await wg.generatePrivateKey();
      const publicKey = await wg.getPublicKey(privateKey);

      await Database.interfaces.updateKeyPair(privateKey, publicKey);
      wgInterface = await Database.interfaces.get();
      WG_DEBUG('New Wireguard Keys generated successfully.');
    }

    WG_DEBUG(`Starting Wireguard Interface ${wgInterface.name}...`);
    await this.#saveWireguardConfig(wgInterface);
    await wg.down(wgInterface.name).catch(() => {});
    await wg.up(wgInterface.name).catch((err: unknown) => {
      if (
        err instanceof Error &&
        err.message.includes(`Cannot find device "${wgInterface.name}"`)
      ) {
        throw new Error(
          `WireGuard exited with the error: Cannot find device "${wgInterface.name}"\nThis usually means that your host's kernel does not support WireGuard!`,
          { cause: err.message }
        );
      }

      throw err;
    });
    await this.#syncWireguardConfig(wgInterface);
    WG_DEBUG(`Wireguard Interface ${wgInterface.name} started successfully.`);

    if (wgInterface.firewallEnabled) {
      const iptablesAvailable = await firewall.isAvailable();
      if (!iptablesAvailable) {
        const requiredTools = WG_ENV.DISABLE_IPV6
          ? 'iptables'
          : 'iptables/ip6tables';
        console.warn(
          `WARNING: Per-Client Firewall is enabled but ${requiredTools} is not available. Disabling firewall feature. Please install ${requiredTools} to use this feature.`
        );
        await Database.interfaces.setFirewallEnabled(false);
        wgInterface.firewallEnabled = false;
      }
    }

    WG_DEBUG('Applying firewall rules...');
    await this.#applyFirewallRules(wgInterface);
    WG_DEBUG('Firewall rules applied successfully.');

    this.#startCronJob();
  }

  #startCronJob() {
    const run = () =>
      this.cronJob().catch((err) => {
        WG_DEBUG('Running Cron Job failed.');
        console.error(err);
      });
    run();
    setInterval(run, 60 * 1000);
  }

  async Shutdown() {
    const wgInterface = await Database.interfaces.get();
    await wg.down(wgInterface.name).catch(() => {});
  }

  async cronJob() {
    const now = Date.now();
    let needsSave = false;
    for (const client of await Database.clients.getAll()) {
      if (
        client.enabled &&
        client.expiresAt !== null &&
        now > Date.parse(client.expiresAt)
      ) {
        WG_DEBUG(`Client ${client.id} expired.`);
        await Database.clients.toggle(client.id, false);
        needsSave = true;
      }
      if (
        client.installLink !== null &&
        now > Date.parse(client.installLink.expiresAt)
      ) {
        WG_DEBUG(`InstallLink for Client ${client.id} expired.`);
        await Database.installLinks.delete(client.id);
      }
    }

    if (needsSave) {
      await this.saveConfig();
    }
  }
}

export default new WireGuard();
