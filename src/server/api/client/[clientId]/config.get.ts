export default defineClientHandler('view', async ({ event, client }) => {
  const config = await WireGuard.getClientFullConfig({ clientId: client.id });
  setHeader(event, 'Content-Type', 'text/plain; charset=utf-8');
  return config;
});
