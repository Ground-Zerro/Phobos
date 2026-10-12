import type { InferSelectModel } from 'drizzle-orm';
import z from 'zod';
import isCidr from 'is-cidr';
import { isIP } from 'is-ip';
import type { wgInterface } from './schema';

export type InterfaceType = InferSelectModel<typeof wgInterface>;

export type InterfaceUpdateType = Omit<
  InterfaceType,
  'name' | 'createdAt' | 'updatedAt' | 'privateKey' | 'publicKey'
>;

type InterfaceAdminUpdateType = Omit<
  InterfaceUpdateType,
  'port' | 'ipv4Cidr' | 'ipv6Cidr'
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

const ServerPublicIpV4Schema = z
  .string({ message: t('zod.obfuscator.publicIpV4') })
  .refine((v) => isIP(v) && !v.includes(':'), {
    message: t('zod.obfuscator.publicIpV4'),
  });

const ServerPublicIpV6Schema = z
  .string({ message: t('zod.obfuscator.publicIpV6') })
  .refine((v) => isIP(v) && v.includes(':'), {
    message: t('zod.obfuscator.publicIpV6'),
  })
  .nullable();

const ServerPublicDomainSchema = z
  .string()
  .refine(
    (v) =>
      /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/.test(
        v
      ),
    { message: t('zod.interface.domainValid') }
  )
  .nullable();

export const InterfaceUpdateSchema = schemaForType<InterfaceAdminUpdateType>()(
  z.object({
    mtu: MtuSchema,
    device: device,
    enabled: EnabledSchema,
    firewallEnabled: EnabledSchema,
    egressMode: z.enum(['wan', 'warp'], {
      message: t('zod.interface.egressMode'),
    }),
    serverPublicIpV4: ServerPublicIpV4Schema,
    serverPublicIpV6: ServerPublicIpV6Schema,
    serverPublicDomain: ServerPublicDomainSchema,
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
