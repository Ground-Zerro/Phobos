export default definePermissionEventHandler('admin', 'any', async () => {
  await requireWarpRegistered();
  return { online: await WarpInterface.connectivityCheck() };
});
