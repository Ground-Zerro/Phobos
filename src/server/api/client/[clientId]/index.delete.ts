import { ClientGetSchema } from '#db/repositories/client/types';

export default definePermissionEventHandler(
  'clients',
  'delete',
  async ({ event, checkPermissions }) => {
    const { clientId } = await getValidatedRouterParams(
      event,
      validateZod(ClientGetSchema, event)
    );

    const client = await Database.clients.get(clientId);
    checkPermissions(client);

    await Database.clients.delete(clientId);
    await WireGuard.saveConfig();
    await Obfuscator.applyAll();
    PhobosPackage.invalidate(clientId);
    return { success: true };
  }
);
