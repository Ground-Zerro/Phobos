export default defineEventHandler(async (event) => {
  const { client } = await resolveInstallClient(event);
  const archive = await PhobosPackage.build(client.id);
  setHeader(event, 'Content-Type', 'application/gzip');
  setHeader(
    event,
    'Content-Disposition',
    `attachment; filename="${PhobosPackage.filename(client)}"`
  );
  setHeader(event, 'Content-Length', archive.length);
  setHeader(event, 'Cache-Control', 'no-store');
  return archive;
});
