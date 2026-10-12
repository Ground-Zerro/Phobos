import packageJson from '@@/package.json';
import { readRuntimeEnv } from './env';
import { createLogger } from './logger';

export const RELEASE = 'v' + packageJson.version;

export const TOTP_ISSUER = 'PhobosWG';

export const SERVER_DEBUG = createLogger('Server');

export const WG_ENV = {
  INSECURE: process.env.INSECURE === 'true',
  PORT: assertEnv('PORT'),
  DISABLE_IPV6: process.env.DISABLE_IPV6 === 'true',
  WG_EXECUTABLE: 'wg' as const,
};

export const WG_INITIAL_ENV = {
  ENABLED: process.env.INIT_ENABLED === 'true',
  USERNAME: process.env.INIT_USERNAME,
  PASSWORD: process.env.INIT_PASSWORD,
  DNS: process.env.INIT_DNS?.split(',').map((x) => x.trim()),
  IPV4_CIDR: process.env.INIT_IPV4_CIDR,
  IPV6_CIDR: process.env.INIT_IPV6_CIDR,
  ALLOWED_IPS: process.env.INIT_ALLOWED_IPS?.split(',').map((x) => x.trim()),
  HOST: process.env.INIT_HOST,
};

function assertEnv<T extends string>(env: T) {
  const val = readRuntimeEnv(env);

  if (!val) {
    throw new Error(`Missing environment variable: ${env}`);
  }

  return val;
}
