import {
  ClientGetSchema,
  ClientUpdateSchema,
} from '#db/repositories/client/types';

export default definePermissionEventHandler(
  'clients',
  'update',
  async ({ event, checkPermissions }) => {
    const { clientId } = await getValidatedRouterParams(
      event,
      validateZod(ClientGetSchema, event)
    );

    const data = await readValidatedBody(
      event,
      validateZod(ClientUpdateSchema, event)
    );

    const client = await Database.clients.get(clientId);
    checkPermissions(client);

    if (data.presetId != null) {
      try {
        await Database.obfuscatorPresets.get(data.presetId);
      } catch (e) {
        throw createError({
          statusCode: 400,
          statusMessage: (e as Error).message,
        });
      }
    }

    await Database.clients.update(clientId, data);
    await WireGuard.saveConfig();
    await Obfuscator.applyAll();
    PhobosPackage.invalidate(clientId);

    return { success: true };
  }
);
