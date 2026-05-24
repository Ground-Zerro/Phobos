import type { InferSelectModel } from 'drizzle-orm';
import z from 'zod';
import isCidr from 'is-cidr';
import { isIP } from 'is-ip';
import type { wgInterface } from './schema';

export type InterfaceType = InferSelectModel<typeof wgInterface>;

export type InterfaceCreateType = Omit<
  InterfaceType,
  'createdAt' | 'updatedAt'
>;

export type InterfaceUpdateType = Omit<
  InterfaceCreateType,
  'name' | 'createdAt' | 'updatedAt' | 'privateKey' | 'publicKey'
>;

/** Admin/API updates: internal WG listen port and local client port are fixed in DB. */
export type InterfaceAdminUpdateType = Omit<
  InterfaceUpdateType,
  'port' | 'clientWgLocalPort'
>;

const device = z
  .string({ message: t('zod.interface.device') })
  .min(1, t('zod.interface.device'))
  .pipe(safeStringRefine);

const cidr = z
  .string({ message: t('zod.interface.cidr') })
  .min(1, { message: t('zod.interface.cidr') })
  .refine((value) => isCidr(value), { message: t('zod.interface.cidrValid') })
  .pipe(safeStringRefine);

export const ObfuscatorExtPortSchema = z
  .number({ message: t('zod.obfuscator.extPort') })
  .int()
  .min(1024, { message: t('zod.obfuscator.extPort') })
  .max(65535, { message: t('zod.obfuscator.extPort') });

export const ObfuscatorKeySchema = z
  .string({ message: t('zod.obfuscator.key') })
  .min(3)
  .max(255)
  .pipe(safeStringRefine);

export const ObfuscatorMaskingSchema = z.enum(['STUN', 'AUTO', 'NONE'], {
  message: t('zod.obfuscator.masking'),
});

export const ObfuscatorIdleSchema = z
  .number({ message: t('zod.obfuscator.idle') })
  .int()
  .min(30)
  .max(3600);

export const ObfuscatorDummySchema = z
  .number({ message: t('zod.obfuscator.dummy') })
  .int()
  .min(0)
  .max(255);

export const ServerPublicIpV4Schema = z
  .string({ message: t('zod.obfuscator.publicIpV4') })
  .refine((v) => isIP(v) && !v.includes(':'), {
    message: t('zod.obfuscator.publicIpV4'),
  });

export const ServerPublicIpV6Schema = z
  .string({ message: t('zod.obfuscator.publicIpV6') })
  .refine((v) => isIP(v) && v.includes(':'), {
    message: t('zod.obfuscator.publicIpV6'),
  })
  .nullable();

export const InterfaceUpdateSchema = schemaForType<InterfaceAdminUpdateType>()(
  z.object({
    ipv4Cidr: cidr,
    ipv6Cidr: cidr,
    mtu: MtuSchema,
    device: device,
    enabled: EnabledSchema,
    firewallEnabled: EnabledSchema,
    obfuscatorExtPort: ObfuscatorExtPortSchema,
    obfuscatorKey: ObfuscatorKeySchema,
    obfuscatorMasking: ObfuscatorMaskingSchema,
    obfuscatorIdle: ObfuscatorIdleSchema,
    obfuscatorDummy: ObfuscatorDummySchema,
    serverPublicIpV4: ServerPublicIpV4Schema,
    serverPublicIpV6: ServerPublicIpV6Schema,
  })
);

export type InterfaceCidrUpdateType = {
  ipv4Cidr: string;
  ipv6Cidr: string;
};

export const InterfaceCidrUpdateSchema =
  schemaForType<InterfaceCidrUpdateType>()(
    z.object({
      ipv4Cidr: cidr,
      ipv6Cidr: cidr,
    })
  );
