export default definePermissionEventHandler('admin', 'any', async () => {
  const iface = await Database.interfaces.get();
  const length = Math.max(iface.obfuscatorKey.length || 16, 16);
  const key = Obfuscator.generateKey(length);

  await Database.interfaces.update({
    obfuscatorKey: key,
  });

  const updated = await Database.interfaces.get();
  await Obfuscator.apply(updated);
  PhobosPackage.invalidate();

  return { key };
});
