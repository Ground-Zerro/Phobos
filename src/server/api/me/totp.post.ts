import { Secret } from 'otpauth';
import { createTotp } from '#db/repositories/user/service';
import { UserUpdateTotpSchema } from '#db/repositories/user/types';

export default definePermissionEventHandler(
  'me',
  'update',
  async ({ event, user, checkPermissions }) => {
    const body = await readValidatedBody(
      event,
      validateZod(UserUpdateTotpSchema, event)
    );

    checkPermissions(user);

    if (body.type === 'setup') {
      const key = new Secret({ size: 20 });

      const totp = createTotp(user.username, key.base32);

      await Database.users.updateTotpKey(user.id, key.base32);

      return {
        success: true,
        type: 'setup' as const,
        key: key.base32,
        uri: totp.toString(),
      };
    }

    if (body.type === 'create') {
      await Database.users.verifyTotp(user.id, body.code);
      return { success: true, type: 'created' as const };
    }

    await Database.users.deleteTotpKey(user.id, body.currentPassword);
    return { success: true, type: 'deleted' as const };
  }
);
