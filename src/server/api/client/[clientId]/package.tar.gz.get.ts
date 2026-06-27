import { ClientGetSchema } from '#db/repositories/client/types';

export default definePermissionEventHandler(
  'clients',
  'view',
  async ({ event, checkPermissions }) => {
    const { clientId } = await getValidatedRouterParams(
      event,
      validateZod(ClientGetSchema, event)
    );

    const client = await Database.clients.get(clientId);
    checkPermissions(client);

    if (!client) {
      throw createError({
        statusCode: 404,
        statusMessage: 'Client not found',
      });
    }

    const buf = await PhobosPackage.build(clientId);
    const filename = await PhobosPackage.getFilename(clientId);

    setHeader(event, 'Content-Type', 'application/gzip');
    setHeader(
      event,
      'Content-Disposition',
      `attachment; filename="${filename}"`
    );
    setHeader(event, 'Content-Length', buf.length);
    return buf;
  }
);
