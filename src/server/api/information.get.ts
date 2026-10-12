import { readTlsOrigin, isUntrustedTls } from '~~/server/utils/TlsInfo';

export default defineEventHandler(async () => {
  const wgInterface = await Database.interfaces.get();

  return {
    currentRelease: RELEASE,
    firewallEnabled: wgInterface.firewallEnabled,
    tlsUntrusted: isUntrustedTls(readTlsOrigin()),
  };
});
