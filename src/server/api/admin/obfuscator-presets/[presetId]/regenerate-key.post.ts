import { ObfuscatorPresetGetSchema } from '#db/repositories/obfuscatorPreset/types';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const { presetId } = await getValidatedRouterParams(
      event,
      validateZod(ObfuscatorPresetGetSchema, event)
    );

    const preset = await Database.obfuscatorPresets.regenerateKey(presetId);
    await Obfuscator.applyAll();
    PhobosPackage.invalidate();
    return preset;
  }
);
