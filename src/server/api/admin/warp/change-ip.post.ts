export default definePermissionEventHandler('admin', 'any', async () => {
  await requireWarpRegistered();
  await asBadRequest(() => WarpInterface.changeIp());
  return maskedWarp();
});
