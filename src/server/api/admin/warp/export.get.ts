export default definePermissionEventHandler('admin', 'any', async () => {
  await requireWarpRegistered();
  const warp = await Database.warp.get();
  return WarpInterface.buildUserConfig(warp, !WG_ENV.DISABLE_IPV6);
});
