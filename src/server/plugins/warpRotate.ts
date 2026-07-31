const CHECK_INTERVAL_MS = 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

export default defineNitroPlugin((nitroApp) => {
  async function tick() {
    try {
      const warp = await Database.warp.get();
      if (warp.updateIntervalDays <= 0 || warp.deviceId === '') {
        return;
      }

      const now = Date.now();

      if (!warp.lastUpdateAt) {
        await Database.warp.setLastUpdateAt(new Date(now).toISOString());
        return;
      }

      const elapsed = now - new Date(warp.lastUpdateAt).getTime();
      if (elapsed < warp.updateIntervalDays * DAY_MS) {
        return;
      }

      console.log('[warpRotate] rotating WARP IP...');
      await WarpInterface.changeIp();
      console.log('[warpRotate] WARP IP rotated');
    } catch (e) {
      console.warn(
        `[warpRotate] rotation check failed: ${(e as Error).message}`
      );
    }
  }

  const timer = setInterval(tick, CHECK_INTERVAL_MS);

  nitroApp.hooks.hook('close', () => {
    clearInterval(timer);
  });
});
