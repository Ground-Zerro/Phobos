<template>
  <button
    class="inline-flex items-center gap-1 rounded p-2 align-middle text-xs transition"
    :class="
      isActive
        ? 'bg-green-100 text-green-700 hover:bg-red-800 hover:text-white dark:bg-green-900 dark:text-green-300 dark:hover:bg-red-800 dark:hover:text-white'
        : 'bg-gray-100 hover:bg-red-800 hover:text-white dark:bg-neutral-600 dark:text-neutral-300 dark:hover:bg-red-800 dark:hover:text-white'
    "
    :title="$t('client.copyInstallLink')"
    @click="copyInstallLink"
  >
    <IconsLink class="w-5 shrink-0" />
    <span v-if="isActive" class="tabular-nums">{{ countdown }}</span>
  </button>
</template>

<script setup lang="ts">
const props = defineProps<{ client: LocalClient }>();
const { t } = useI18n();
const toast = useToast();
const globalStore = useGlobalStore();
const copy = useCopyToClipboard();

const expiresAt = ref<number>(0);

const secondsLeft = ref(0);

const isActive = computed(() => secondsLeft.value > 0);

const countdown = computed(() => {
  const m = Math.floor(secondsLeft.value / 60);
  const s = secondsLeft.value % 60;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
});

const { pause, resume } = useIntervalFn(
  () => {
    const remaining = Math.max(0, Math.floor((expiresAt.value - Date.now()) / 1000));
    secondsLeft.value = remaining;
    if (remaining === 0) pause();
  },
  1000,
  { immediate: false }
);

async function copyInstallLink() {
  try {
    const { token, expiresAt: expiresAtStr } = await $fetch<{
      token: string;
      expiresAt: string;
    }>(`/api/client/${props.client.id}/generateInstallLink`, { method: 'post' });

    expiresAt.value = new Date(expiresAtStr).getTime();
    secondsLeft.value = Math.max(
      0,
      Math.floor((expiresAt.value - Date.now()) / 1000)
    );
    resume();

    const untrusted =
      window.location.protocol === 'https:' &&
      Boolean(globalStore.information?.tlsUntrusted);
    const curlFlags = untrusted ? '-ksL' : '-sL';
    const command = `curl ${curlFlags} ${window.location.origin}/api/install/${token} | sh`;

    await copy(command);

    toast.showToast({
      type: 'success',
      message: t('client.installLinkCopied'),
    });
  } catch {
    toast.showToast({
      type: 'error',
      message: t('client.installLinkFailed'),
    });
  }
}
</script>
