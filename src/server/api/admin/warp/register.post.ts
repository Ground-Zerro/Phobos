export default definePermissionEventHandler('admin', 'any', async () => {
  await asBadRequest(() => WarpInterface.register());
  return maskedWarp();
});
