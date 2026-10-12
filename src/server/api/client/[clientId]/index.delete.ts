export default defineClientHandler('delete', async ({ client }) => {
  await Database.clients.delete(client.id);
  await WireGuard.saveConfig();
  await Obfuscator.applyAll();
  PhobosPackage.invalidate(client.id);
  return { success: true };
});
