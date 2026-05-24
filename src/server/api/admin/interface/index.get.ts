export default definePermissionEventHandler('admin', 'any', async () => {
  const wgInterface = await Database.interfaces.get();
  const { privateKey, port, clientWgLocalPort, ...rest } = wgInterface;
  void privateKey;
  void port;
  void clientWgLocalPort;
  return {
    ...rest,
    privateKey: undefined,
  };
});
