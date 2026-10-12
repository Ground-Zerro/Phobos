import { InterfaceUpdateSchema } from '#db/repositories/interface/types';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const data = await readValidatedBody(
      event,
      validateZod(InterfaceUpdateSchema, event)
    );

    if (data.firewallEnabled) {
      firewall.clearAvailabilityCache();

      const iptablesAvailable = await firewall.isAvailable();
      if (!iptablesAvailable) {
        const requiredTools = WG_ENV.DISABLE_IPV6
          ? 'iptables'
          : 'iptables and ip6tables';
        throw createError({
          statusCode: 400,
          statusMessage: `Per-Client Firewall requires ${requiredTools} to be installed on the host system. Please install ${requiredTools} before enabling this feature.`,
        });
      }
    }

    const prev = await Database.interfaces.get();
    const publicIpChanged =
      prev.serverPublicIpV4 !== data.serverPublicIpV4 ||
      prev.serverPublicIpV6 !== data.serverPublicIpV6;

    if (data.egressMode === 'warp' && !(await Database.warp.isRegistered())) {
      throw createError({
        statusCode: 400,
        statusMessage:
          'WARP egress requires a registered WARP configuration. Register WARP first.',
      });
    }

    await Database.interfaces.update(data);
    await WireGuard.saveConfig();

    if (data.egressMode === 'warp' && prev.egressMode !== 'warp') {
      try {
        await WarpInterface.enable();
      } catch (e) {
        throw createError({
          statusCode: 400,
          statusMessage: (e as Error).message,
        });
      }
    } else if (data.egressMode !== 'warp' && prev.egressMode === 'warp') {
      await WarpInterface.disable();
    }

    if (publicIpChanged) {
      await Obfuscator.applyAll();
    }

    PhobosPackage.invalidate();

    return { success: true };
  }
);
