export default definePresetMutation(async ({ presetId }) => {
  await Database.obfuscatorPresets.setDefault(presetId);
  return { success: true };
});
