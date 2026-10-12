import { connect, type DBServiceType } from '#db/sqlite';

let provider: DBServiceType | null = null;

const Database = new Proxy({} as DBServiceType, {
  get(_, key: keyof DBServiceType) {
    if (!provider) {
      throw new Error('Database not yet initialized');
    }
    return provider[key];
  },
});

connect().then(async (db) => {
  provider = db;
  await WireGuard.Startup();
  await Obfuscator.Startup();
  await WarpInterface.Startup();
});

export default Database;
