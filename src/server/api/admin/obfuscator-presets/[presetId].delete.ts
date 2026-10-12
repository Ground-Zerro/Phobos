export default definePresetMutation(async ({ presetId }) => {
  await Database.obfuscatorPresets.delete(presetId);
  return { success: true };
});
