import { WarpUpdateSchema } from '#db/repositories/warp/types';
import { maskWarp } from '#db/repositories/warp/service';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const data = await readValidatedBody(
      event,
      validateZod(WarpUpdateSchema, event)
    );

    if (!(await Database.warp.isRegistered())) {
      throw createError({
        statusCode: 400,
        statusMessage: 'WARP is not registered.',
      });
    }

    await Database.warp.update(data);

    try {
      await WarpInterface.reapply();
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
