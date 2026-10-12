export function useClientConfig(configUrl: MaybeRefOrGetter<string>) {
  const toast = useToast();
  const copy = useCopyToClipboard();

  const open = ref(false);
  const config = ref<string | null>(null);
  const loading = ref(false);

  async function load() {
    if (config.value || loading.value) return;
    loading.value = true;
    try {
      config.value = await $fetch<string>(toValue(configUrl), {
        responseType: 'text',
      });
    } catch (e) {
      console.error('failed to fetch config', e);
    } finally {
      loading.value = false;
    }
  }

  watch(open, (isOpen) => {
    if (isOpen) load();
  });

  async function copyText(
    text: string | null,
    messages: { success: string; failure: string }
  ) {
    if (!text) {
      load();
      toast.showToast({ type: 'error', message: messages.failure });
      return;
    }
    try {
      await copy(text);
      toast.showToast({ type: 'success', message: messages.success });
    } catch (e) {
      console.error('failed to copy', e);
      toast.showToast({ type: 'error', message: messages.failure });
    }
  }

  return { open, config, copyText };
}
