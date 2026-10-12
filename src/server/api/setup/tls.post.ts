export default defineSetupEventHandler('tls', async ({ event }) => {
  const body = await readValidatedBody(
    event,
    validateZod(TlsModeSchema, event)
  );
  const httpsUrl = await applyTlsMode(body);
  await Database.general.setSetupStep(0);
  if (httpsUrl) {
    scheduleNodeRestart();
  }
  return { success: true, httpsUrl };
});
