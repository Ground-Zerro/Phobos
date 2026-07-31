import { ObfuscatorPresetGetSchema } from '#db/repositories/obfuscatorPreset/types';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const { presetId } = await getValidatedRouterParams(
      event,
      validateZod(ObfuscatorPresetGetSchema, event)
    );

    let preset;
    try {
      preset = await Database.obfuscatorPresets.regeneratePort(presetId);
    } catch (e) {
      throw createError({
        statusCode: 400,
        statusMessage: (e as Error).message,
      });
    }

    await Obfuscator.applyAll();
    PhobosPackage.invalidate();
    return preset;
  }
);
