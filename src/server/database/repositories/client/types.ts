import type { InferSelectModel } from 'drizzle-orm';
import z from 'zod';

import type { client } from './schema';

export type ClientType = InferSelectModel<typeof client>;

export type ClientNextIpType = Pick<ClientType, 'ipv4Address' | 'ipv6Address'>;

export type CreateClientType = Omit<
  ClientType,
  'createdAt' | 'updatedAt' | 'id'
>;

export type UpdateClientType = Omit<
  CreateClientType,
  | 'privateKey'
  | 'publicKey'
  | 'preSharedKey'
  | 'userId'
  | 'interfaceId'
  | 'socks5Login'
  | 'socks5Password'
>;

const name = z
  .string({ message: t('zod.client.name') })
  .trim()
  .min(1, t('zod.client.name'))
  .max(CLIENT_NAME_MAX_LENGTH, t('zod.client.nameTooLong'))
  .regex(CLIENT_NAME_PATTERN, t('zod.client.nameInvalidChars'))
  .pipe(safeStringRefine);

// TODO?: validate iso string
const expiresAt = z
  .string({ message: t('zod.client.expiresAt') })
  .min(1, t('zod.client.expiresAt'))
  .pipe(safeStringRefine)
  .nullable();

const address4 = z
  .string({ message: t('zod.client.address4') })
  .min(1, { message: t('zod.client.address4') })
  .pipe(safeStringRefine);

const address6 = z
  .string({ message: t('zod.client.address6') })
  .min(1, { message: t('zod.client.address6') })
  .pipe(safeStringRefine);

const filter = z.string().optional();

const serverAllowedIps = z.array(AddressSchema, {
  message: t('zod.client.serverAllowedIps'),
});

const presetIdSchema = z
  .number({ message: t('zod.client.presetId') })
  .int()
  .nullable()
  .optional();

export const ClientCreateSchema = z.object({
  name: name,
  expiresAt: expiresAt,
  presetId: presetIdSchema,
});

export type ClientCreateType = z.infer<typeof ClientCreateSchema>;

export const ClientQuerySchema = z.object({
  filter: filter,
});

export type ClientQueryType = z.infer<typeof ClientQuerySchema>;

export const ClientUpdateSchema = schemaForType<UpdateClientType>()(
  z.object({
    name: name,
    enabled: EnabledSchema,
    expiresAt: expiresAt,
    ipv4Address: address4,
    ipv6Address: address6,
    preUp: HookSchema,
    postUp: HookSchema,
    preDown: HookSchema,
    postDown: HookSchema,
    allowedIps: AllowedIpsSchema.nullable(),
    serverAllowedIps: serverAllowedIps,
    firewallIps: FirewallIpsSchema.nullable(),
    mtu: MtuSchema,
    persistentKeepalive: PersistentKeepaliveSchema,
    serverEndpoint: AddressSchema.nullable(),
    dns: DnsSchema.nullable(),
    presetId: z.number().int().nullable(),
  })
);

// TODO: investigate if coerce is bad
const clientId = z.coerce.number({ message: t('zod.client.id') });

export const ClientGetSchema = z.object({
  clientId: clientId,
});

export type ClientCreateFromExistingType = Pick<
  ClientType,
  | 'name'
  | 'ipv4Address'
  | 'ipv6Address'
  | 'privateKey'
  | 'preSharedKey'
  | 'publicKey'
  | 'enabled'
>;
