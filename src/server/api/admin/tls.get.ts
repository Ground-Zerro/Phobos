import { readTlsOrigin } from '~~/server/utils/TlsInfo';

export default definePermissionEventHandler('admin', 'any', async () => {
  return {
    origin: readTlsOrigin(),
  };
});
