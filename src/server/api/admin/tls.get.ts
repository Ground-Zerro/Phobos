import {
  readTlsOrigin,
  hasActiveTlsCert,
  isExternalTlsManaged,
} from '~~/server/utils/TlsInfo';

export default definePermissionEventHandler('admin', 'any', async () => {
  return {
    origin: readTlsOrigin(),
    hasCert: hasActiveTlsCert(),
    externalManaged: isExternalTlsManaged(),
  };
});
