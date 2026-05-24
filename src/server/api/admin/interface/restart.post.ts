export default definePermissionEventHandler('admin', 'any', async () => {
  await WireGuard.Restart();

  const iface = await Database.interfaces.get();
  await Obfuscator.apply(iface);
  PhobosPackage.invalidate();

  return { success: true };
});
