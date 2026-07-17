import { ClientCreateSchema } from '#db/repositories/client/types';

export default definePermissionEventHandler(
  'clients',
  'create',
  async ({ event }) => {
    const { name, expiresAt, presetId } = await readValidatedBody(
      event,
      validateZod(ClientCreateSchema, event)
    );

    if (presetId != null) {
      try {
        await Database.obfuscatorPresets.get(presetId);
      } catch (e) {
        throw createError({
          statusCode: 400,
          statusMessage: (e as Error).message,
        });
      }
    }

    const result = await Database.clients.create({ name, expiresAt, presetId });
    await WireGuard.saveConfig();
    await Obfuscator.applyAll();

    const clientId = result[0]!.clientId;
    return { success: true, clientId };
  }
);
