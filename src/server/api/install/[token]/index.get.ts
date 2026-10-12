export default defineEventHandler(async (event) => {
  const { token, client } = await resolveInstallClient(event);
  const script = PhobosPackage.installScript(
    client,
    token,
    getRequestURL(event).origin
  );
  setHeader(event, 'Content-Type', 'text/x-shellscript; charset=utf-8');
  setHeader(event, 'Cache-Control', 'no-store');
  return script;
});
