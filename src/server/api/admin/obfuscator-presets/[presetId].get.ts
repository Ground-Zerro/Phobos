import { ObfuscatorPresetGetSchema } from '#db/repositories/obfuscatorPreset/types';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const { presetId } = await getValidatedRouterParams(
      event,
      validateZod(ObfuscatorPresetGetSchema, event)
    );
    return Database.obfuscatorPresets.get(presetId);
  }
);
