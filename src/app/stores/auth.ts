import type { H3Event } from 'h3';
import type { SharedPublicUser } from '~~/shared/utils/permissions';

export const useAuthStore = defineStore('Auth', () => {
  const userData = useState<SharedPublicUser | null>('user-data', () => null);

  async function getSession(event?: H3Event) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const fetch = (event as any)?.$fetch ?? ($fetch as any);
    try {
      const data = await fetch('/api/session', {
        method: 'get',
      });
      return data;
    } catch {
      return null;
    }
  }

  async function update() {
    const data = await getSession();
    userData.value = data;
  }

  return { userData, update, getSession };
});
