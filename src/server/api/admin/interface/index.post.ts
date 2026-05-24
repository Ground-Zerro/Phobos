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

      const iptablesAvailable = await firewall.isAvailable(
        !WG_ENV.DISABLE_IPV6
      );
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

    const obfuscatorChanged =
      prev.obfuscatorExtPort !== data.obfuscatorExtPort ||
      prev.obfuscatorKey !== data.obfuscatorKey ||
      prev.obfuscatorMasking !== data.obfuscatorMasking ||
      prev.obfuscatorIdle !== data.obfuscatorIdle ||
      prev.obfuscatorDummy !== data.obfuscatorDummy ||
      prev.serverPublicIpV4 !== data.serverPublicIpV4 ||
      prev.serverPublicIpV6 !== data.serverPublicIpV6 ||
      prev.clientWgLocalPort !== data.clientWgLocalPort;

    await Database.interfaces.update(data);
    await WireGuard.saveConfig();

    if (obfuscatorChanged) {
      const updated = await Database.interfaces.get();
      await Obfuscator.apply(updated);
    }

    PhobosPackage.invalidate();

    return { success: true };
  }
);
