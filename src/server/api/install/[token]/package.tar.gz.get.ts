import { InstallTokenParamSchema } from '#db/repositories/installLink/types';

export default defineEventHandler(async (event) => {
  const { token } = await getValidatedRouterParams(
    event,
    validateZod(InstallTokenParamSchema, event)
  );

  const link = await Database.installLinks.getActiveByToken(token);
  if (!link) {
    throw createError({
      statusCode: 404,
      statusMessage: 'Install link not found',
    });
  }

  const client = await Database.clients.get(link.id);
  if (!client) {
    throw createError({
      statusCode: 404,
      statusMessage: 'Client not found',
    });
  }

  const buf = await PhobosPackage.build(link.id);
  const filename = await PhobosPackage.getFilename(link.id);

  setHeader(event, 'Content-Type', 'application/gzip');
  setHeader(
    event,
    'Content-Disposition',
    `attachment; filename="${filename}"`
  );
  setHeader(event, 'Content-Length', buf.length);
  setHeader(event, 'Cache-Control', 'no-store');
  return buf;
});
