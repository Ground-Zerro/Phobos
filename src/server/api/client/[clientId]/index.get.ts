export default defineClientHandler('view', async ({ client }) => {
  const [endpoint, preset] = await Promise.all([
    WireGuard.peerEndpoint(client.publicKey),
    Database.obfuscatorPresets.getForClient(client.presetId),
  ]);

  return {
    ...client,
    endpoint,
    preset: {
      id: preset.id,
      name: preset.name,
      isDefault: preset.isDefault,
      mode: preset.mode,
    },
  };
});
