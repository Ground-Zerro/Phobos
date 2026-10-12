import { ClientUpdateSchema } from '#db/repositories/client/types';

export default defineClientHandler('update', async ({ event, client }) => {
  const data = await readValidatedBody(
    event,
    validateZod(ClientUpdateSchema, event)
  );
  await Database.clients.update(client.id, data);
  await WireGuard.saveConfig();
  await Obfuscator.applyAll();
  PhobosPackage.invalidate(client.id);
  return { success: true };
});
