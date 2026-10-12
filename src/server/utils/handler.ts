import type { EventHandlerRequest, EventHandlerResponse, H3Event } from 'h3';
import type { UserType } from '#db/repositories/user/types';
import {
  ClientGetSchema,
  type ClientType,
} from '#db/repositories/client/types';
import { ObfuscatorPresetGetSchema } from '#db/repositories/obfuscatorPreset/types';
import { maskWarp } from '#db/repositories/warp/service';
import { InstallTokenParamSchema } from '#db/repositories/installLink/types';
import type { SetupStepType } from '#db/repositories/general/types';
import {
  type Permissions,
  hasPermissionsWithData,
} from '#shared/utils/permissions';

type PermissionHandler<
  TReq extends EventHandlerRequest,
  TRes extends EventHandlerResponse,
  Resource extends keyof Permissions,
> = {
  (params: {
    event: H3Event<TReq>;
    user: UserType;
    checkPermissions: (data?: Permissions[Resource]['dataType']) => true;
  }): TRes;
};

export const definePermissionEventHandler = <
  TReq extends EventHandlerRequest,
  TRes extends EventHandlerResponse,
  Resource extends keyof Permissions,
>(
  resource: Resource,
  action: Permissions[Resource]['action'],
  handler: PermissionHandler<TReq, TRes, Resource>
) => {
  return defineEventHandler(async (event) => {
    const user = await getCurrentUser(event);

    const permissions = hasPermissionsWithData(user, resource, action);

    const checkPermissions = (data?: Permissions[Resource]['dataType']) => {
      if (!permissions.check(data)) {
        throw createError({
          statusCode: 403,
          statusMessage: 'Permission denied',
        });
      }
      return true as const;
    };

    if (permissions.isBoolean()) {
      checkPermissions();
    }

    const response = await handler({ event, user, checkPermissions });

    if (!permissions.checked) {
      throw createError({
        statusCode: 500,
        statusMessage: 'Permission was not checked',
      });
    }

    return response;
  });
};

export async function asBadRequest<T>(work: () => Promise<T>): Promise<T> {
  try {
    return await work();
  } catch (e) {
    throw createError({ statusCode: 400, statusMessage: (e as Error).message });
  }
}

export const defineClientHandler = <TRes extends EventHandlerResponse>(
  action: Permissions['clients']['action'],
  handler: (params: {
    event: H3Event;
    user: UserType;
    client: ClientType;
  }) => TRes
) =>
  definePermissionEventHandler(
    'clients',
    action,
    async ({ event, user, checkPermissions }) => {
      const { clientId } = await getValidatedRouterParams(
        event,
        validateZod(ClientGetSchema, event)
      );
      const client = await Database.clients.get(clientId);
      if (!client) {
        throw createError({
          statusCode: 404,
          statusMessage: 'Client not found',
        });
      }
      checkPermissions(client);
      return handler({ event, user, client });
    }
  );

export async function refreshObfuscation() {
  await Obfuscator.applyAll();
  PhobosPackage.invalidate();
}

export const definePresetMutation = <T>(
  handler: (params: { event: H3Event; presetId: number }) => Promise<T>
) =>
  definePermissionEventHandler('admin', 'any', async ({ event }) => {
    const { presetId } = await getValidatedRouterParams(
      event,
      validateZod(ObfuscatorPresetGetSchema, event)
    );
    const result = await asBadRequest(() => handler({ event, presetId }));
    await refreshObfuscation();
    return result;
  });

export async function requireWarpRegistered() {
  if (!(await Database.warp.isRegistered())) {
    throw createError({
      statusCode: 400,
      statusMessage: 'WARP is not registered.',
    });
  }
}

export async function maskedWarp() {
  return maskWarp(await Database.warp.get());
}

export async function resolveInstallClient(event: H3Event) {
  const { token } = await getValidatedRouterParams(
    event,
    validateZod(InstallTokenParamSchema, event)
  );
  const link = await Database.installLinks.getActiveByToken(token);
  const client = link ? await Database.clients.get(link.id) : undefined;
  if (!client) {
    throw createError({
      statusCode: 404,
      statusMessage: 'Install link not found',
    });
  }
  return { token, client };
}

const ValidSetupSteps = {
  1: [2] as const,
  3: [3] as const,
  4: ['tls'] as const,
} as const;

type ValidSteps =
  (typeof ValidSetupSteps)[keyof typeof ValidSetupSteps][number];

type SetupHandler<
  TReq extends EventHandlerRequest,
  TRes extends EventHandlerResponse,
> = { (params: { event: H3Event<TReq>; setup: SetupStepType }): TRes };

export const defineSetupEventHandler = <
  TReq extends EventHandlerRequest,
  TRes extends EventHandlerResponse,
>(
  step: ValidSteps,
  handler: SetupHandler<TReq, TRes>
) => {
  return defineEventHandler(async (event) => {
    const setup = await Database.general.getSetupStep();

    if (setup.done) {
      throw createError({
        statusCode: 400,
        statusMessage: 'Invalid state',
      });
    }

    const validSetupSteps =
      ValidSetupSteps[setup.step as keyof typeof ValidSetupSteps];

    if (!validSetupSteps) {
      throw createError({
        statusCode: 500,
        statusMessage: 'Invalid setup step',
      });
    }

    if (!validSetupSteps.includes(step as never)) {
      throw createError({
        statusCode: 400,
        statusMessage: 'Invalid step',
      });
    }

    return await handler({ event, setup });
  });
};

type Metrics = 'prometheus' | 'json';

const metricsTokens = new CachedTokenVerifier();

type MetricsHandler<
  TReq extends EventHandlerRequest,
  TRes extends EventHandlerResponse,
> = { (params: { event: H3Event<TReq> }): TRes };

export const defineMetricsHandler = <
  TReq extends EventHandlerRequest,
  TRes extends EventHandlerResponse,
>(
  type: Metrics,
  handler: MetricsHandler<TReq, TRes>
) => {
  return defineEventHandler(async (event) => {
    const metricsConfig = await Database.general.getMetricsConfig();

    if (metricsConfig.password) {
      const auth = getHeader(event, 'Authorization');

      if (!auth) {
        throw createError({
          statusCode: 401,
          statusMessage: 'Unauthorized',
        });
      }

      const [method, value] = auth.split(' ');

      if (method !== 'Bearer' || !value) {
        throw createError({
          statusCode: 401,
          statusMessage: 'Bearer Auth required',
        });
      }

      const tokenValid = await metricsTokens.verify(
        value,
        metricsConfig.password
      );

      if (!tokenValid) {
        throw createError({
          statusCode: 401,
          statusMessage: 'Incorrect token',
        });
      }
    }

    if (metricsConfig[type] !== true) {
      throw createError({
        statusCode: 400,
        statusMessage: 'Metrics not enabled',
      });
    }

    return await handler({ event });
  });
};
