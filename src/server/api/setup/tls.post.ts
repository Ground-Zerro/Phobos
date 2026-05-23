import { z } from 'zod';
import {
  hasActiveTlsCert,
  isExternalTlsManaged,
} from '~~/server/utils/TlsInfo';

const TlsSetupSchema = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('self-signed') }),
  z.object({
    mode: z.literal('import'),
    cert: z.string().min(1),
    key: z.string().min(1),
  }),
  z.object({
    mode: z.literal('letsencrypt'),
    domain: z
      .string()
      .min(1)
      .regex(
        /^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$/,
        'Invalid domain name'
      ),
  }),
  z.object({ mode: z.literal('letsencrypt-ip') }),
  z.object({ mode: z.literal('skip') }),
]);

export default defineSetupEventHandler('tls', async ({ event }) => {
  const body = await readValidatedBody(event, validateZod(TlsSetupSchema, event));

  if (isExternalTlsManaged()) {
    if (!hasActiveTlsCert() && body.mode !== 'skip') {
      throw createError({
        statusCode: 400,
        statusMessage:
          'TLS is managed by the external reverse proxy. Issue or activate the certificate on the host, then continue setup.',
      });
    }

    await Database.general.setAllowInsecureHttpLogin(false);
    await Database.general.setSetupStep(0);
    return { success: true, httpsUrl: null };
  }

  if (body.mode === 'skip') {
    await Database.general.setAllowInsecureHttpLogin(true);
    await Database.general.setSetupStep(0);
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
    } else if (body.mode === 'letsencrypt') {
      await issueLetsEncrypt(body.domain);
    } else if (body.mode === 'letsencrypt-ip') {
      await issueLetsEncryptIp(host);
    }
  } catch (e) {
    const raw = e instanceof Error ? e.message : String(e);
    const firstLine = raw.split('\n').find((l) => l.trim().length > 0) ?? raw;
    throw createError({ statusCode: 400, statusMessage: firstLine });
  }

  await Database.general.setSetupStep(0);

  scheduleNodeRestart();

  return {
    success: true,
    httpsUrl: `https://${host}:${port}/login`,
  };
});
