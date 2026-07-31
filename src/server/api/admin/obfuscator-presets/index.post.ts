import { ObfuscatorPresetCreateSchema } from '#db/repositories/obfuscatorPreset/types';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const data = await readValidatedBody(
      event,
      validateZod(ObfuscatorPresetCreateSchema, event)
    );

    let preset;
    try {
      preset = await Database.obfuscatorPresets.create(data);
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
