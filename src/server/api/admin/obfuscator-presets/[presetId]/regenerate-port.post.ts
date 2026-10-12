export default definePresetMutation(({ presetId }) =>
  Database.obfuscatorPresets.regeneratePort(presetId)
);
