import { z } from 'zod';

const tokenType = z
  .string({ message: t('zod.installLink.token') })
  .length(32, { message: t('zod.installLink.token') })
  .regex(/^[a-f0-9]{32}$/, { message: t('zod.installLink.token') })
  .pipe(safeStringRefine);

export const InstallTokenParamSchema = z.object({
  token: tokenType,
});
