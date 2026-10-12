export default definePermissionEventHandler('admin', 'any', async () => {
  const {
    privateKey: _privateKey,
    port: _port,
    ...rest
  } = await Database.interfaces.get();
  return rest;
});
