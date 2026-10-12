export default defineClientHandler('view', async ({ event, client }) => {
  const svg = await WireGuard.getClientQRCodeSVG({ clientId: client.id });
  setHeader(event, 'Content-Type', 'image/svg+xml');
  return svg;
});
