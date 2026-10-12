import { ClientCreateSchema } from '#db/repositories/client/types';

export default definePermissionEventHandler(
  'clients',
  'create',
  async ({ event, user }) => {
    const data = await readValidatedBody(
      event,
      validateZod(ClientCreateSchema, event)
    );
    const [created] = await Database.clients.create(user.id, data);
    await WireGuard.saveConfig();
    await Obfuscator.applyAll();
    return { success: true, clientId: created!.clientId };
  }
);
