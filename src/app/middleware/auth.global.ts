export default defineNuxtRouteMiddleware(async (to) => {
  if (to.path.startsWith('/api/') || to.path.startsWith('/setup')) {
    return;
  }

  const event = useRequestEvent();

  const authStore = useAuthStore();
  authStore.userData = await authStore.getSession(event);

  if (to.path === '/login') {
    if (authStore.userData?.username) {
      return navigateTo('/', { redirectCode: 302 });
    }
    return;
  }

  if (!authStore.userData?.username) {
    return navigateTo('/login', { redirectCode: 302 });
  }

  if (to.path.startsWith('/admin')) {
    if (!hasPermissions(authStore.userData, 'admin', 'any')) {
      return abortNavigation('Not allowed to access Admin Panel');
    }
  }
});
