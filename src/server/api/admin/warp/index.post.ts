import { WarpUpdateSchema } from '#db/repositories/warp/types';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const data = await readValidatedBody(
      event,
      validateZod(WarpUpdateSchema, event)
    );
    await requireWarpRegistered();
    await Database.warp.update(data);
    await asBadRequest(() => WarpInterface.reapply());
    return maskedWarp();
  }
);
