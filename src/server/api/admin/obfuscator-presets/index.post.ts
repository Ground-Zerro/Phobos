import { ObfuscatorPresetCreateSchema } from '#db/repositories/obfuscatorPreset/types';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const data = await readValidatedBody(
      event,
      validateZod(ObfuscatorPresetCreateSchema, event)
    );
    const preset = await asBadRequest(() =>
      Database.obfuscatorPresets.create(data)
    );
    await refreshObfuscation();
    return preset;
  }
);
