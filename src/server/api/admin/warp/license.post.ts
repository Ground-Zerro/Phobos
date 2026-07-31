import { WarpLicenseSchema } from '#db/repositories/warp/types';
import { maskWarp } from '#db/repositories/warp/service';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const { license } = await readValidatedBody(
      event,
      validateZod(WarpLicenseSchema, event)
    );

    try {
      await WarpInterface.setLicense(license);
    } catch (e) {
      throw createError({
        statusCode: 400,
        statusMessage: (e as Error).message,
      });
    }

    const warp = await Database.warp.get();
    return maskWarp(warp);
  }
);
