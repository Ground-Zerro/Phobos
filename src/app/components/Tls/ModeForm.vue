<template>
  <div class="flex flex-col gap-3">
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
        <span class="font-medium text-gray-800 dark:text-neutral-200">{{
          opt.label
        }}</span>
        <span class="mt-0.5 text-sm text-gray-500 dark:text-neutral-400">{{
          opt.desc
        }}</span>
      </button>
    </div>

    <div v-if="mode === 'import'" class="flex flex-col gap-3">
      <div
        v-for="field in pemFields"
        :key="field.label"
        class="flex flex-col gap-1"
      >
        <label class="text-sm text-gray-500 dark:text-neutral-300">
          {{ $t(field.label) }}
        </label>
        <textarea
          v-model="pem[field.key]"
          rows="6"
          :placeholder="field.placeholder"
          class="w-full rounded-lg border-2 border-gray-100 px-3 py-2 font-mono text-xs text-gray-700 focus:border-red-800 focus:outline-0 dark:border-neutral-800 dark:bg-neutral-700 dark:text-neutral-200"
        />
      </div>
    </div>

    <div v-if="mode === 'import-path'" class="flex flex-col gap-3">
      <div
        v-for="field in pathFields"
        :key="field.label"
        class="flex flex-col gap-1"
      >
        <label class="text-sm text-gray-500 dark:text-neutral-300">
          {{ $t(field.label) }}
        </label>
        <BaseInput
          v-model.trim="paths[field.key]"
          type="text"
          class="w-full"
          :placeholder="field.placeholder"
        />
      </div>
      <p class="text-xs text-amber-600 dark:text-amber-400">
        {{ $t('setup.tls.importPathHint') }}
      </p>
    </div>

    <div
      v-if="warning"
      class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-700 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-400"
    >
      {{ warning }}
    </div>

    <div :class="actionsClass">
      <BaseButton
        variant="primary"
        :disabled="submitting || !canSubmit"
        class="disabled:cursor-not-allowed disabled:opacity-50"
        @click="submit"
      >
        {{ submitLabel(mode) }}
      </BaseButton>
    </div>
  </div>
</template>

<script setup lang="ts">
type TlsMode = 'self-signed' | 'import' | 'import-path' | 'skip';

const props = defineProps<{
  submitting: boolean;
  submitLabel: (mode: TlsMode) => string;
  actionsClass?: string;
}>();

const emit = defineEmits<{ submit: [body: Record<string, string>] }>();

const { t } = useI18n();

const mode = ref<TlsMode>('self-signed');
const pem = reactive({ cert: '', key: '' });
const paths = reactive({ certPath: '', keyPath: '' });

const pemFields = [
  {
    key: 'cert',
    label: 'setup.tls.certLabel',
    placeholder: '-----BEGIN CERTIFICATE-----\n...',
  },
  {
    key: 'key',
    label: 'setup.tls.keyLabel',
    placeholder: '-----BEGIN PRIVATE KEY-----\n...',
  },
] as const;

const pathFields = [
  {
    key: 'certPath',
    label: 'setup.tls.certPathLabel',
    placeholder: '/root/cert/example.com/fullchain.pem',
  },
  {
    key: 'keyPath',
    label: 'setup.tls.keyPathLabel',
    placeholder: '/root/cert/example.com/privkey.pem',
  },
] as const;

const modes = computed<{ value: TlsMode; label: string; desc: string }[]>(
  () => [
    {
      value: 'self-signed',
      label: t('setup.tls.selfSigned'),
      desc: t('setup.tls.selfSignedDesc'),
    },
    {
      value: 'import',
      label: t('setup.tls.import'),
      desc: t('setup.tls.importDesc'),
    },
    {
      value: 'import-path',
      label: t('setup.tls.importPath'),
      desc: t('setup.tls.importPathDesc'),
    },
    {
      value: 'skip',
      label: t('setup.tls.skip'),
      desc: t('setup.tls.skipDesc'),
    },
  ]
);

const warning = computed(() => {
  if (mode.value === 'self-signed') return t('setup.tls.selfSignedHstsWarning');
  if (mode.value === 'skip') return t('setup.tls.skipWarning');
  return null;
});

const canSubmit = computed(() => {
  if (mode.value === 'import') {
    return pem.cert.trim().length > 0 && pem.key.trim().length > 0;
  }
  if (mode.value === 'import-path') {
    return paths.certPath.length > 0 && paths.keyPath.length > 0;
  }
  return true;
});

function submit() {
  if (props.submitting || !canSubmit.value) return;
  if (mode.value === 'import') {
    emit('submit', {
      mode: 'import',
      cert: pem.cert.trim(),
      key: pem.key.trim(),
    });
  } else if (mode.value === 'import-path') {
    emit('submit', { mode: 'import-path', ...paths });
  } else {
    emit('submit', { mode: mode.value });
  }
}

function reset() {
  pem.cert = '';
  pem.key = '';
  paths.certPath = '';
  paths.keyPath = '';
}

defineExpose({ reset });
</script>
