import { WarpIntervalSchema } from '#db/repositories/warp/types';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const { updateIntervalDays } = await readValidatedBody(
      event,
      validateZod(WarpIntervalSchema, event)
    );

    await Database.warp.update({ updateIntervalDays });

    return { success: true };
  }
);
