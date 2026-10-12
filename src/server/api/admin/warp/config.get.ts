export default definePermissionEventHandler('admin', 'any', async () => {
  await requireWarpRegistered();
  return asBadRequest(() => WarpInterface.remoteConfig());
});
