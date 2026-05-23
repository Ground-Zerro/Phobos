<template>
  <div>
    <p class="text-center text-lg">
      {{ $t('setup.tls.desc') }}
    </p>

    <div v-if="!restarting" class="mt-6 flex flex-col gap-4">
      <div class="flex flex-col gap-2">
        <button
          v-for="opt in modes"
          :key="opt.value"
          type="button"
          class="flex flex-col rounded-lg border-2 px-4 py-3 text-left transition"
          :class="
            mode === opt.value
              ? 'border-red-800 bg-red-50 dark:bg-red-900/20'
              : 'border-gray-100 hover:border-gray-300 dark:border-neutral-700 dark:hover:border-neutral-500'
          "
          @click="mode = opt.value"
        >
          <span class="font-medium text-gray-800 dark:text-neutral-200">{{ opt.label }}</span>
          <span class="mt-0.5 text-sm text-gray-500 dark:text-neutral-400">{{ opt.desc }}</span>
        </button>
      </div>

      <div v-if="mode === 'import'" class="flex flex-col gap-3">
        <div class="flex flex-col gap-1">
          <label class="text-sm text-gray-500 dark:text-neutral-300">
            {{ $t('setup.tls.certLabel') }}
          </label>
          <textarea
            v-model="importCert"
            rows="6"
            placeholder="-----BEGIN CERTIFICATE-----&#10;..."
            class="w-full rounded-lg border-2 border-gray-100 px-3 py-2 font-mono text-xs text-gray-700 focus:border-red-800 focus:outline-0 dark:border-neutral-800 dark:bg-neutral-700 dark:text-neutral-200"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm text-gray-500 dark:text-neutral-300">
            {{ $t('setup.tls.keyLabel') }}
          </label>
          <textarea
            v-model="importKey"
            rows="6"
            placeholder="-----BEGIN PRIVATE KEY-----&#10;..."
            class="w-full rounded-lg border-2 border-gray-100 px-3 py-2 font-mono text-xs text-gray-700 focus:border-red-800 focus:outline-0 dark:border-neutral-800 dark:bg-neutral-700 dark:text-neutral-200"
          />
        </div>
      </div>

      <div v-if="mode === 'import-path'" class="flex flex-col gap-3">
        <div class="flex flex-col gap-1">
          <label class="text-sm text-gray-500 dark:text-neutral-300">
            {{ $t('setup.tls.certPathLabel') }}
          </label>
          <BaseInput
            v-model.trim="importCertPath"
            type="text"
            class="w-full"
            placeholder="/etc/letsencrypt/live/example.com/fullchain.pem"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm text-gray-500 dark:text-neutral-300">
            {{ $t('setup.tls.keyPathLabel') }}
          </label>
          <BaseInput
            v-model.trim="importKeyPath"
            type="text"
            class="w-full"
            placeholder="/etc/letsencrypt/live/example.com/privkey.pem"
          />
        </div>
        <p class="text-xs text-amber-600 dark:text-amber-400">
          {{ $t('setup.tls.importPathHint') }}
        </p>
      </div>

      <div
        v-if="mode === 'skip'"
        class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-700 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-400"
      >
        {{ $t('setup.tls.skipWarning') }}
      </div>

      <div class="flex justify-center">
        <BasePrimaryButton
          :disabled="submitting || !canSubmit"
          class="disabled:cursor-not-allowed disabled:opacity-50"
          @click="submit"
        >
          {{ mode === 'skip' ? $t('general.continue') : $t('setup.tls.generate') }}
        </BasePrimaryButton>
      </div>
    </div>

    <div v-else class="mt-8 flex flex-col items-center gap-6 text-center">
      <svg class="h-12 w-12 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
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
        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
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

const setupStore = useSetupStore();
setupStore.setStep(5);

const { t } = useI18n();
const toast = useToast();

type Mode = 'self-signed' | 'import' | 'import-path' | 'skip';

const mode = ref<Mode>('self-signed');
const importCert = ref('');
const importKey = ref('');
const importCertPath = ref('');
const importKeyPath = ref('');
const submitting = ref(false);
const restarting = ref(false);
const httpsUrl = ref('');
const countdown = ref(0);

const modes = computed<{ value: Mode; label: string; desc: string }[]>(() => [
  { value: 'self-signed', label: t('setup.tls.selfSigned'), desc: t('setup.tls.selfSignedDesc') },
  { value: 'import',      label: t('setup.tls.import'),     desc: t('setup.tls.importDesc') },
  { value: 'import-path', label: t('setup.tls.importPath'), desc: t('setup.tls.importPathDesc') },
  { value: 'skip',        label: t('setup.tls.skip'),       desc: t('setup.tls.skipDesc') },
]);

const canSubmit = computed(() => {
  if (mode.value === 'import') {
    return importCert.value.trim().length > 0 && importKey.value.trim().length > 0;
  }
  if (mode.value === 'import-path') {
    return importCertPath.value.trim().length > 0 && importKeyPath.value.trim().length > 0;
  }
  return true;
});

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

async function submit() {
  if (submitting.value || !canSubmit.value) return;
  submitting.value = true;

  try {
    let body: Record<string, string>;
    if (mode.value === 'import') {
      body = {
        mode: 'import',
        cert: importCert.value.trim(),
        key: importKey.value.trim(),
      };
    } else if (mode.value === 'import-path') {
      body = {
        mode: 'import-path',
        certPath: importCertPath.value.trim(),
        keyPath: importKeyPath.value.trim(),
      };
    } else {
      body = { mode: mode.value };
    }

    const result = await $fetch<{ success: boolean; httpsUrl: string | null }>(
      '/api/setup/tls',
      { method: 'post', body }
    );

    if (result.httpsUrl) {
      httpsUrl.value = result.httpsUrl;
      restarting.value = true;
      countdown.value = 25;
      resume();
    } else {
      window.location.href = '/login';
    }
  } catch (e: unknown) {
    const msg =
      e && typeof e === 'object' && 'data' in e && e.data && typeof e.data === 'object' && 'message' in e.data
        ? String((e.data as { message: string }).message)
        : t('toast.unknown');
    toast.showToast({ type: 'error', message: msg });
  } finally {
    submitting.value = false;
  }
}
</script>
