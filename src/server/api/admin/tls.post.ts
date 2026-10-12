export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const body = await readValidatedBody(
      event,
      validateZod(TlsModeSchema, event)
    );
    const httpsUrl = await applyTlsMode(body);
    scheduleNodeRestart();
    return { success: true, httpsUrl };
  }
);
