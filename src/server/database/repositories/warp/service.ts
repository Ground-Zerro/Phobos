import { eq } from 'drizzle-orm';
import { warp } from './schema';
import type {
  WarpManualType,
  WarpRegistrationType,
  WarpType,
  WarpUpdateType,
} from './types';
import { Repository } from '#db/repository';
import type { DBType } from '#db/sqlite';

const WARP_ROW_ID = 1;
const byRow = eq(warp.id, WARP_ROW_ID);

function maskSecret(value: string): string {
  if (value.length <= 8) {
    return value ? '••••' : '';
  }
  return `${value.slice(0, 4)}••••${value.slice(-4)}`;
}

export function maskWarp(row: WarpType) {
  return {
    registered: row.deviceId !== '',
    deviceId: maskSecret(row.deviceId),
    accessToken: maskSecret(row.accessToken),
    licenseKey: maskSecret(row.licenseKey),
    hasLicense: row.licenseKey !== '',
    peerPublicKey: row.peerPublicKey,
    endpoint: row.endpoint,
    addressV4: row.addressV4,
    addressV6: row.addressV6,
    mtu: row.mtu,
    dns: row.dns,
    hasPresharedKey: row.presharedKey !== '',
    persistentKeepalive: row.persistentKeepalive,
    updateIntervalDays: row.updateIntervalDays,
    lastUpdateAt: row.lastUpdateAt,
  };
}

function createPreparedStatement(db: DBType) {
  return {
    get: db.query.warp.findFirst({ where: eq(warp.id, WARP_ROW_ID) }).prepare(),
  };
}

export class WarpService extends Repository<
  ReturnType<typeof createPreparedStatement>
> {
  constructor(db: DBType) {
    super(db, createPreparedStatement);
  }

  async get() {
    const row = await this.statements.get.execute();
    if (!row) {
      throw new Error('Warp config not found');
    }
    return row;
  }

  async isRegistered() {
    const row = await this.get();
    return row.deviceId !== '';
  }

  update(
    data:
      | WarpRegistrationType
      | Partial<WarpUpdateType>
      | Partial<WarpManualType>
      | Partial<
          Pick<WarpType, 'licenseKey' | 'updateIntervalDays' | 'lastUpdateAt'>
        >
  ) {
    return this.db.update(warp).set(data).where(byRow).execute();
  }

  clear() {
    return this.db.transaction(async (tx) => {
      await tx.delete(warp).where(byRow).execute();
      await tx.insert(warp).values({ id: WARP_ROW_ID }).execute();
    });
  }
}
