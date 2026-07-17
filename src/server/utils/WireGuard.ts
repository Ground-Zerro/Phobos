import fs from 'node:fs/promises';
import debug from 'debug';
import type { InterfaceType } from '#db/repositories/interface/types';

const WG_DEBUG = debug('WireGuard');

class WireGuard {
  /**
   * Save and sync config
   */
  async saveConfig() {
    const wgInterface = await Database.interfaces.get();
    await this.#saveWireguardConfig(wgInterface);
    await this.#syncWireguardConfig(wgInterface);
    await this.#applyFirewallRules(wgInterface);
  }

  async saveConfigAndRestart() {
    const wgInterface = await Database.interfaces.get();
    await wg.down(wgInterface.name).catch(() => {});
    await this.#saveWireguardConfig(wgInterface);
    await wg.up(wgInterface.name);
    await this.#applyFirewallRules(wgInterface);
  }

  /**
   * Apply firewall rules based on current config
   */
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

  /**
   * Generates and saves WireGuard config from database
   *
   * Make sure to pass an updated InterfaceType object
   */
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
    const wgInterface = await Database.interfaces.get();
    const defaultPreset = await Database.obfuscatorPresets.getDefault();
    const defaultPresetInfo = {
      id: defaultPreset.id,
      name: defaultPreset.name,
      isDefault: defaultPreset.isDefault,
      mode: defaultPreset.mode,
    };

    const clients = dbClients.map((client) => ({
      ...client,
      preset: client.preset ?? defaultPresetInfo,
      latestHandshakeAt: null as Date | null,
      endpoint: null as string | null,
      transferRx: null as number | null,
      transferTx: null as number | null,
    }));

    const dump = await wg.dump(wgInterface.name);
    for (const {
      publicKey,
      latestHandshakeAt,
      endpoint,
      transferRx,
      transferTx,
    } of dump) {
      const client = clients.find((client) => client.publicKey === publicKey);
      if (!client) {
        continue;
      }

      client.latestHandshakeAt = latestHandshakeAt;
      client.endpoint = endpoint;
      client.transferRx = transferRx;
      client.transferTx = transferTx;
    }

    if (clients.some((client) => client.preset.mode === 'SOCKS5')) {
      const socks5Stats = await Obfuscator.readSocks5Stats();
      for (const client of clients) {
        if (client.preset.mode !== 'SOCKS5' || !client.socks5Login) {
          continue;
        }
        const stats = socks5Stats.get(client.socks5Login);
        if (!stats) {
          client.latestHandshakeAt = null;
          client.transferRx = null;
          client.transferTx = null;
          continue;
        }
        client.transferRx = stats.upBytes;
        client.transferTx = stats.downBytes;
        client.latestHandshakeAt =
          stats.conns > 0
            ? new Date()
            : stats.idleMs >= 0
              ? new Date(Date.now() - stats.idleMs)
              : null;
      }
    }

    return clients;
  }

  async dumpByPublicKey(publicKey: string) {
    const wgInterface = await Database.interfaces.get();

    const dump = await wg.dump(wgInterface.name);
    const clientDump = dump.find(
      ({ publicKey: dumpPublicKey }) => dumpPublicKey === publicKey
    );

    return clientDump;
  }

  async getAllClients(filter?: string) {
    const dbClients = filter?.trim()
      ? await Database.clients.getAllPublicFiltered(filter)
      : await Database.clients.getAllPublic();
    return this.#attachRuntimeStats(dbClients);
  }

  async getClientConfiguration({ clientId }: { clientId: ID }) {
    const wgInterface = await Database.interfaces.get();
    const userConfig = await Database.userConfigs.get();

    const client = await Database.clients.get(clientId);

    if (!client) {
      throw new Error('Client not found');
    }

    const preset = await Database.obfuscatorPresets.getForClient(
      client.presetId ?? null
    );

    return wg.generateClientConfig(wgInterface, userConfig, client, {
      enableIpv6: !WG_ENV.DISABLE_IPV6,
      clientWgLocalPort: preset.clientWgLocalPort,
    });
  }

  async getClientFullConfig({ clientId }: { clientId: ID }) {
    const [iface, client] = await Promise.all([
      Database.interfaces.get(),
      Database.clients.get(clientId),
    ]);
    const preset = await Database.obfuscatorPresets.getForClient(
      client?.presetId ?? null
    );

    if (preset.mode === 'SOCKS5') {
      const obfConf = Obfuscator.buildSocks5ClientObfConf(preset, iface);
      const { login, password } =
        await Database.clients.ensureSocks5Credentials(clientId);
      const credentials = Obfuscator.buildSocks5CredentialsSection(
        login,
        password
      );
      return `${obfConf.replace(/\s+$/, '')}\n\n${credentials}`;
    }

    const wgConfig = await this.getClientConfiguration({ clientId });
    return `${wgConfig.replace(/\s+$/, '')}\n\n${Obfuscator.buildClientObfConf(preset, iface)}`;
  }

  async getClientQRCodeSVG({ clientId }: { clientId: ID }) {
    const config = await this.getClientFullConfig({ clientId });
    return encodeQRCode(config);
  }

  cleanClientFilename(name: string): string {
    return name
      .replace(/[^a-zA-Z0-9_=+.-]/g, '-')
      .replace(/(-{2,}|-$)/g, '-')
      .replace(/-$/, '')
      .substring(0, 32);
  }

  async Startup() {
    WG_DEBUG('Starting WireGuard...');
    // let as it has to refetch if keys change
    let wgInterface = await Database.interfaces.get();

    // default interface has no keys
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
    await wg.up(wgInterface.name).catch((err) => {
      if (
        err &&
        err.message &&
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

    // Check if firewall was enabled but iptables isn't available
    if (wgInterface.firewallEnabled) {
      const enableIpv6 = !WG_ENV.DISABLE_IPV6;
      const iptablesAvailable = await firewall.isAvailable(enableIpv6);
      if (!iptablesAvailable) {
        const requiredTools = enableIpv6 ? 'iptables/ip6tables' : 'iptables';
        console.warn(
          `WARNING: Per-Client Firewall is enabled but ${requiredTools} is not available. Disabling firewall feature. Please install ${requiredTools} to use this feature.`
        );
        await Database.interfaces.setFirewallEnabled(false);
        wgInterface.firewallEnabled = false; // Update local copy
      }
    }

    WG_DEBUG('Applying firewall rules...');
    await this.#applyFirewallRules(wgInterface);
    WG_DEBUG('Firewall rules applied successfully.');

    WG_DEBUG('Starting Cron Job...');
    await this.startCronJob();
    WG_DEBUG('Cron Job started successfully.');
  }

  // TODO: handle as worker_thread
  async startCronJob() {
    setIntervalImmediately(() => {
      this.cronJob().catch((err) => {
        WG_DEBUG('Running Cron Job failed.');
        console.error(err);
      });
    }, 60 * 1000);
  }

  // Shutdown wireguard
  async Shutdown() {
    const wgInterface = await Database.interfaces.get();
    await wg.down(wgInterface.name).catch(() => {});
  }

  async Restart() {
    const wgInterface = await Database.interfaces.get();
    await wg.restart(wgInterface.name);
  }

  async cronJob() {
    const clients = await Database.clients.getAll();
    let needsSave = false;
    // Expires Feature
    for (const client of clients) {
      if (client.enabled !== true) continue;
      if (
        client.expiresAt !== null &&
        new Date() > new Date(client.expiresAt)
      ) {
        WG_DEBUG(`Client ${client.id} expired.`);
        await Database.clients.toggle(client.id, false);
        needsSave = true;
      }
    }
    for (const client of clients) {
      if (
        client.installLink !== null &&
        new Date() > new Date(client.installLink.expiresAt)
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

if (OLD_ENV.PASSWORD || OLD_ENV.PASSWORD_HASH) {
  throw new Error(
    `
You are using an invalid Configuration for wg-easy
Please follow the instructions on https://wg-easy.github.io/wg-easy/latest/advanced/migrate/from-14-to-15/ to migrate
`
  );
}

// TODO: make static or object

export default new WireGuard();
