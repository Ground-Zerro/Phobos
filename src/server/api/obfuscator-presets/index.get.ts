export default definePermissionEventHandler('clients', 'custom', async () => {
  const presets = await Database.obfuscatorPresets.list();
  return presets.map(({ id, name, isDefault, mode }) => ({
    id,
    name,
    isDefault,
    mode,
  }));
});
