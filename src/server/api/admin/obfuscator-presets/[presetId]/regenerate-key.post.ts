export default definePresetMutation(({ presetId }) =>
  Database.obfuscatorPresets.regenerateKey(presetId)
);
