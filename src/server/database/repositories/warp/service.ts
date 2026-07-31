import { eq } from 'drizzle-orm';
import { warp } from './schema';
import type {
  WarpManualType,
  WarpRegistrationType,
  WarpType,
  WarpUpdateType,
} from './types';
import type { DBType } from '#db/sqlite';

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

export class WarpService {
  #db: DBType;

  constructor(db: DBType) {
    this.#db = db;
  }

  async get() {
    const row = await this.#db.query.warp.findFirst({ where: eq(warp.id, 1) });

    if (!row) {
      throw new Error('Warp config not found');
    }

    return row;
  }

  async isRegistered() {
    const row = await this.get();
    return row.deviceId !== '';
  }

  setRegistration(data: WarpRegistrationType) {
    return this.#db.update(warp).set(data).where(eq(warp.id, 1)).execute();
  }

  update(data: Partial<WarpUpdateType> | Partial<WarpManualType>) {
    return this.#db.update(warp).set(data).where(eq(warp.id, 1)).execute();
  }

  setLicenseKey(licenseKey: string) {
    return this.#db
      .update(warp)
      .set({ licenseKey })
      .where(eq(warp.id, 1))
      .execute();
  }

  setUpdateInterval(updateIntervalDays: number) {
    return this.#db
      .update(warp)
      .set({ updateIntervalDays })
      .where(eq(warp.id, 1))
      .execute();
  }

  setLastUpdateAt(lastUpdateAt: string | null) {
    return this.#db
      .update(warp)
      .set({ lastUpdateAt })
      .where(eq(warp.id, 1))
      .execute();
  }

  clear() {
    return this.#db
      .update(warp)
      .set({
        accessToken: '',
        deviceId: '',
        licenseKey: '',
        privateKey: '',
        clientId: '',
        peerPublicKey: '',
        endpoint: 'engage.cloudflareclient.com:2408',
        addressV4: '',
        addressV6: '',
        mtu: 1280,
        presharedKey: '',
        dns: '',
        persistentKeepalive: 25,
        updateIntervalDays: 0,
        lastUpdateAt: null,
      })
      .where(eq(warp.id, 1))
      .execute();
  }
}
