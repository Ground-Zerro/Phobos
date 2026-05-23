<template>
  <FormGroup>
    <FormHeading :description="$t('admin.tls.desc')">
      {{ $t('admin.tls.title') }}
    </FormHeading>

    <div v-if="status === 'pending'" class="text-sm text-gray-500 dark:text-neutral-400">
      {{ $t('general.loading') }}
    </div>

    <div v-else-if="state" class="flex flex-col gap-3">
      <div class="rounded-lg border border-gray-100 bg-gray-50 px-4 py-3 text-sm dark:border-neutral-700 dark:bg-neutral-800">
        <span class="font-medium text-gray-700 dark:text-neutral-200">{{ $t('admin.tls.current') }}:</span>
        <span class="ml-2 text-gray-600 dark:text-neutral-300">{{ originLabel }}</span>
      </div>

      <div
        v-if="state.externalManaged"
        class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-700 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-400"
      >
        {{ $t('admin.tls.externalManaged') }}
      </div>

      <div v-else class="flex flex-col gap-3">
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

        <div>
          <BasePrimaryButton
            :disabled="submitting || !canSubmit"
            class="disabled:cursor-not-allowed disabled:opacity-50"
            @click="apply"
          >
            {{ $t('admin.tls.apply') }}
          </BasePrimaryButton>
        </div>
      </div>
    </div>
  </FormGroup>
</template>

<script setup lang="ts">
type Origin = 'self-signed' | 'imported' | 'none';
type Mode = 'self-signed' | 'import' | 'import-path' | 'skip';
type TlsState = { origin: Origin; hasCert: boolean; externalManaged: boolean };

const { t } = useI18n();
const toast = useToast();

const { data: state, status, refresh } = await useFetch<TlsState>(
  '/api/admin/tls',
  { method: 'get' }
);

const mode = ref<Mode>('self-signed');
const importCert = ref('');
const importKey = ref('');
const importCertPath = ref('');
const importKeyPath = ref('');
const submitting = ref(false);

const originLabel = computed(() => {
  const o = state.value?.origin ?? 'none';
  return t(`admin.tls.origin.${o}`);
});

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

async function apply() {
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
      '/api/admin/tls',
      { method: 'post', body }
    );

    toast.showToast({
      type: 'success',
      message: result.httpsUrl
        ? t('admin.tls.appliedRestart', { url: result.httpsUrl })
        : t('admin.tls.applied'),
    });

    importCert.value = '';
    importKey.value = '';
    importCertPath.value = '';
    importKeyPath.value = '';

    await refresh();
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
