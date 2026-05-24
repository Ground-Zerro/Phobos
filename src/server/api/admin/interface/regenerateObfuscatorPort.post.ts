export default definePermissionEventHandler('admin', 'any', async () => {
  const envPortRaw = Number(process.env.OBF_PORT);
  if (
    Number.isFinite(envPortRaw) &&
    envPortRaw >= 1024 &&
    envPortRaw <= 65535
  ) {
    throw createError({
      statusCode: 409,
      statusMessage:
        'OBF_PORT pinned via environment; change OBF_PORT and recreate container',
    });
  }

  const port = await Obfuscator.findFreePort();
  await Database.interfaces.update({ obfuscatorExtPort: port });

  const updated = await Database.interfaces.get();
  await Obfuscator.apply(updated);
  PhobosPackage.invalidate();

  return { port };
});
