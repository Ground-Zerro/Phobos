import { z } from 'zod';
import {
  hasActiveTlsCert,
  isExternalTlsManaged,
} from '~~/server/utils/TlsInfo';

const TlsUpdateSchema = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('self-signed') }),
  z.object({
    mode: z.literal('import'),
    cert: z.string().min(1),
    key: z.string().min(1),
  }),
  z.object({
    mode: z.literal('import-path'),
    certPath: z.string().min(1),
    keyPath: z.string().min(1),
  }),
  z.object({ mode: z.literal('skip') }),
]);

export default definePermissionEventHandler('admin', 'any', async ({ event }) => {
  const body = await readValidatedBody(event, validateZod(TlsUpdateSchema, event));

  if (isExternalTlsManaged()) {
    if (!hasActiveTlsCert() && body.mode !== 'skip') {
      throw createError({
        statusCode: 400,
        statusMessage:
          'TLS is managed by the external reverse proxy. Issue or activate the certificate on the host first.',
      });
    }

    await Database.general.setAllowInsecureHttpLogin(false);
    return { success: true, httpsUrl: null };
  }

  if (body.mode === 'skip') {
    await Database.general.setAllowInsecureHttpLogin(true);
    scheduleNodeRestart();
    return { success: true, httpsUrl: null };
  }

  await Database.general.setAllowInsecureHttpLogin(false);

  const userConfig = await Database.userConfigs.get();
  const host = userConfig.host;
  const port = process.env.PORT ?? '51831';

  try {
    if (body.mode === 'self-signed') {
      generateSelfSigned(host);
    } else if (body.mode === 'import') {
      importCert(body.cert, body.key);
    } else if (body.mode === 'import-path') {
      importCertFromPath(body.certPath, body.keyPath);
    }
  } catch (e) {
    const raw = e instanceof Error ? e.message : String(e);
    const firstLine = raw.split('\n').find((l) => l.trim().length > 0) ?? raw;
    throw createError({ statusCode: 400, statusMessage: firstLine });
  }

  scheduleNodeRestart();

  return {
    success: true,
    httpsUrl: `https://${host}:${port}/login`,
  };
});
