export default defineClientHandler('update', async ({ client }) => {
  await Database.clients.toggle(client.id, false);
  await WireGuard.saveConfig();
  await Obfuscator.applyAll();
  return { success: true };
});
