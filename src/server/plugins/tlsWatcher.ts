import { watchFile, unwatchFile } from 'node:fs';

const WATCH_INTERVAL_MS = 30_000;
const RESTART_DEBOUNCE_MS = 5_000;

export default defineNitroPlugin((nitroApp) => {
  const paths = readTlsWatchedPaths();
  if (!paths) return;

  let restartTimer: NodeJS.Timeout | null = null;
  const watched = [paths.certPath, paths.keyPath];

  function onChange(
    curr: { mtimeMs: number; size: number },
    prev: { mtimeMs: number; size: number }
  ) {
    if (curr.mtimeMs === prev.mtimeMs && curr.size === prev.size) return;
    if (restartTimer) return;
    console.log(
      `[tlsWatcher] TLS source file changed, restarting in ${RESTART_DEBOUNCE_MS}ms`
    );
    restartTimer = setTimeout(() => {
      scheduleNodeRestart();
    }, RESTART_DEBOUNCE_MS);
  }

  for (const path of watched) {
    watchFile(
      path,
      { interval: WATCH_INTERVAL_MS, persistent: false },
      onChange
    );
  }
  console.log(
    `[tlsWatcher] watching ${watched.length} TLS source files (interval ${WATCH_INTERVAL_MS}ms)`
  );

  nitroApp.hooks.hook('close', () => {
    for (const path of watched) {
      unwatchFile(path);
    }
    if (restartTimer) {
      clearTimeout(restartTimer);
      restartTimer = null;
    }
  });
});
