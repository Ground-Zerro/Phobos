import { WarpLicenseSchema } from '#db/repositories/warp/types';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const { license } = await readValidatedBody(
      event,
      validateZod(WarpLicenseSchema, event)
    );
    await asBadRequest(() => WarpInterface.setLicense(license));
    return maskedWarp();
  }
);
