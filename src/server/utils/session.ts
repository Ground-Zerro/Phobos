import type { H3Event } from 'h3';
import type { UserType } from '#db/repositories/user/types';
import { hasActiveTlsCert } from '~~/server/utils/TlsInfo';

export type WGSession = Partial<{
  userId: ID;
}>;

async function sessionOptions() {
  const config = await Database.general.getSessionConfig();
  const allowPlainHttp =
    WG_ENV.INSECURE || config.allowInsecureHttpLogin || !hasActiveTlsCert();
  return {
    password: config.sessionPassword,
    name: allowPlainHttp ? 'phobos-h' : 'phobos-s',
    cookie: {
      maxAge: config.sessionTimeout,
      secure: !allowPlainHttp,
      sameSite: 'lax' as const,
    },
  };
}

export async function useWGSession(event: H3Event) {
  return useSession<WGSession>(event, await sessionOptions());
}

export async function getWGSession(event: H3Event) {
  return getSession<WGSession>(event, await sessionOptions());
}

export async function getCurrentUser(event: H3Event) {
  const session = await getWGSession(event);

  const authorization = getHeader(event, 'Authorization');

  let user: UserType | undefined = undefined;
  if (session.data.userId) {
    user = await Database.users.get(session.data.userId);
  } else if (authorization) {
    const [method, value] = authorization.split(' ');
    if (method !== 'Basic' || !value) {
      throw createError({
        statusCode: 400,
        statusMessage: 'Invalid Basic Authorization',
      });
    }

    const basicValue = Buffer.from(value, 'base64').toString('utf-8');

    const index = basicValue.indexOf(':');
    const username = basicValue.substring(0, index);
    const password = basicValue.substring(index + 1);

    if (!username || !password) {
      throw createError({
        statusCode: 400,
        statusMessage: 'Invalid Basic Authorization',
      });
    }

    const foundUser = await Database.users.getByUsername(username);

    if (!foundUser) {
      throw createError({
        statusCode: 401,
        statusMessage: 'Session failed',
      });
    }

    const userHashPassword = foundUser.password;
    const passwordValid = await isPasswordValid(password, userHashPassword);

    if (!passwordValid) {
      throw createError({
        statusCode: 401,
        statusMessage: 'Session failed',
      });
    }
    user = foundUser;
  } else {
    throw createError({
      statusCode: 401,
      statusMessage: 'Session failed. No Authorization',
    });
  }

  if (!user) {
    throw createError({
      statusCode: 401,
      statusMessage: 'Session failed. User not found',
    });
  }

  if (!user.enabled) {
    throw createError({
      statusCode: 403,
      statusMessage: 'User is disabled',
    });
  }

  return user;
}
