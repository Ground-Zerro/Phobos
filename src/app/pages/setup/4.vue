<template>
  <div>
    <p class="text-center text-lg">
      {{ $t('setup.tls.desc') }}
    </p>

    <TlsModeForm
      v-if="!restarting"
      class="mt-6"
      actions-class="flex justify-center"
      :submitting="submitting"
      :submit-label="
        (mode) =>
          mode === 'skip' ? $t('general.continue') : $t('setup.tls.generate')
      "
      @submit="submit"
    />

    <div v-else class="mt-8 flex flex-col items-center gap-6 text-center">
      <svg
        class="h-12 w-12 text-green-500"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
        />
      </svg>
      <p class="text-lg font-medium text-gray-800 dark:text-neutral-200">
        {{ $t('setup.tls.restarting') }}
      </p>
      <p class="text-sm text-gray-500 dark:text-neutral-400">
        {{ $t('setup.tls.redirectPrompt') }}
      </p>
      <a
        :href="httpsUrl"
        class="inline-flex items-center gap-2 rounded-lg bg-red-800 px-6 py-2.5 text-sm font-medium text-white transition hover:bg-red-700"
      >
        <svg
          class="h-4 w-4"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
          />
        </svg>
        {{ $t('setup.tls.openLink') }}
        <span v-if="countdown > 0" class="opacity-70">({{ countdown }})</span>
      </a>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({
  layout: 'setup',
});

const { t } = useI18n();
const toast = useToast();

const submitting = ref(false);
const restarting = ref(false);
const httpsUrl = ref('');
const countdown = ref(0);

const { pause, resume } = useIntervalFn(
  () => {
    countdown.value--;
    if (countdown.value <= 0) {
      pause();
      window.location.href = httpsUrl.value;
    }
  },
  1000,
  { immediate: false }
);

async function submit(body: Record<string, string>) {
  submitting.value = true;
  try {
    const result = await $fetch('/api/setup/tls', { method: 'post', body });
    if (result.httpsUrl) {
      httpsUrl.value = result.httpsUrl;
      restarting.value = true;
      countdown.value = 25;
      resume();
    } else {
      window.location.href = '/login';
    }
  } catch (e) {
    toast.showToast({
      type: 'error',
      message: toErrorMessage(e, t('toast.unknown')),
    });
  } finally {
    submitting.value = false;
  }
}
</script>
