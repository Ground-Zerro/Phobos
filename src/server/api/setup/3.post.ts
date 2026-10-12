import { UserConfigSetupSchema } from '#db/repositories/userConfig/types';

export default defineSetupEventHandler(3, async ({ event }) => {
  const { host } = await readValidatedBody(
    event,
    validateZod(UserConfigSetupSchema, event)
  );

  await Database.userConfigs.update({ host });

  await Database.general.setSetupStep(4);
  return { success: true };
});
