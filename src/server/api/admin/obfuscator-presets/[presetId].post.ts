import { ObfuscatorPresetUpdateSchema } from '#db/repositories/obfuscatorPreset/types';

export default definePresetMutation(async ({ event, presetId }) => {
  const data = await readValidatedBody(
    event,
    validateZod(ObfuscatorPresetUpdateSchema, event)
  );
  return Database.obfuscatorPresets.update(presetId, data);
});
