import { eq, sql } from 'drizzle-orm';
import { parseCidr } from 'cidr-tools';
import { WG_INTERFACE_NAME, wgInterface } from './schema';
import type { InterfaceCidrUpdateType, InterfaceUpdateType } from './types';
import { client as clientSchema } from '#db/schema';
import { Repository } from '#db/repository';
import type { DBType } from '#db/sqlite';

const byName = eq(wgInterface.name, WG_INTERFACE_NAME);

function createPreparedStatement(db: DBType) {
  return {
    get: db.query.wgInterface.findFirst({ where: byName }).prepare(),
    updateKeyPair: db
      .update(wgInterface)
      .set({
        privateKey: sql.placeholder('privateKey') as never as string,
        publicKey: sql.placeholder('publicKey') as never as string,
      })
      .where(byName)
      .prepare(),
    setFirewallEnabled: db
      .update(wgInterface)
      .set({
        firewallEnabled: sql.placeholder('firewallEnabled') as never as boolean,
      })
      .where(byName)
      .prepare(),
  };
}

export class InterfaceService extends Repository<
  ReturnType<typeof createPreparedStatement>
> {
  constructor(db: DBType) {
    super(db, createPreparedStatement);
  }

  async get() {
    const row = await this.statements.get.execute();
    if (!row) {
      throw new Error('Interface not found');
    }
    return row;
  }

  updateKeyPair(privateKey: string, publicKey: string) {
    return this.statements.updateKeyPair.execute({ privateKey, publicKey });
  }

  update(data: Partial<InterfaceUpdateType>) {
    return this.db.update(wgInterface).set(data).where(byName).execute();
  }

  setFirewallEnabled(firewallEnabled: boolean) {
    return this.statements.setFirewallEnabled.execute({ firewallEnabled });
  }

  updateCidr(data: InterfaceCidrUpdateType) {
    return this.db.transaction(async (tx) => {
      const old = await tx.query.wgInterface
        .findFirst({
          where: byName,
          columns: { ipv4Cidr: true, ipv6Cidr: true },
        })
        .execute();
      if (!old) {
        throw new Error('Interface not found');
      }

      await tx.update(wgInterface).set(data).where(byName).execute();

      const remapV4 = data.ipv4Cidr !== old.ipv4Cidr;
      const remapV6 = data.ipv6Cidr !== old.ipv6Cidr;
      if (!remapV4 && !remapV6) return;

      const cidr4 = parseCidr(data.ipv4Cidr);
      const cidr6 = parseCidr(data.ipv6Cidr);
      const clients = await tx.query.client
        .findMany({
          columns: { id: true, ipv4Address: true, ipv6Address: true },
        })
        .execute();
      const taken4 = new Set(clients.map((c) => c.ipv4Address));
      const taken6 = new Set(clients.map((c) => c.ipv6Address));

      for (const client of clients) {
        const ipv4Address =
          remapV4 && !isAssignableIP(cidr4, client.ipv4Address)
            ? nextIP(4, cidr4, taken4)
            : client.ipv4Address;
        const ipv6Address =
          remapV6 && !isAssignableIP(cidr6, client.ipv6Address)
            ? nextIP(6, cidr6, taken6)
            : client.ipv6Address;
        if (
          ipv4Address === client.ipv4Address &&
          ipv6Address === client.ipv6Address
        ) {
          continue;
        }
        taken4.add(ipv4Address);
        taken6.add(ipv6Address);
        await tx
          .update(clientSchema)
          .set({ ipv4Address, ipv6Address })
          .where(eq(clientSchema.id, client.id))
          .execute();
      }
    });
  }
}
