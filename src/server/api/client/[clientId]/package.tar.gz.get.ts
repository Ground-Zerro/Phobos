export default defineClientHandler('view', async ({ event, client }) => {
  const archive = await PhobosPackage.build(client.id);
  setHeader(event, 'Content-Type', 'application/gzip');
  setHeader(
    event,
    'Content-Disposition',
    `attachment; filename="${PhobosPackage.filename(client)}"`
  );
  setHeader(event, 'Content-Length', archive.length);
  return archive;
});
