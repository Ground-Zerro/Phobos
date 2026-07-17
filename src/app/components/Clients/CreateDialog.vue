<template>
  <BaseDialog v-model:open="open" :trigger-class="triggerClass">
    <template #trigger>
      <slot />
    </template>
    <template #title>
      {{ $t('client.new') }}
    </template>
    <template #description>
      <div class="flex flex-col gap-2">
        <div class="flex flex-col gap-1">
          <FormTextField
            id="name"
            v-model="name"
            :label="$t('client.name')"
            :description="$t('client.nameHint')"
          />
          <p v-if="nameError" class="text-xs text-red-500">
            {{ nameError }}
          </p>
        </div>
        <FormDateField
          id="expiresAt"
          v-model="expiresAt"
          :label="$t('client.expireDate')"
        />
        <div class="flex flex-col gap-1">
          <FormLabel for="presetId">{{ $t('client.preset') }}</FormLabel>
          <select
            id="presetId"
            v-model="presetId"
            class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
          >
            <option :value="null">{{ $t('client.presetUseDefault') }}</option>
            <option v-for="p in selectablePresets" :key="p.id" :value="p.id">
              {{ p.name }} ({{ p.mode === 'SOCKS5' ? 'SOCKS5' : 'WireGuard' }})
            </option>
          </select>
        </div>
      </div>
    </template>
    <template #actions>
      <DialogClose as-child>
        <BaseSecondaryButton>{{ $t('dialog.cancel') }}</BaseSecondaryButton>
      </DialogClose>
      <BasePrimaryButton
        :disabled="!nameValid"
        :class="{ 'cursor-not-allowed opacity-50': !nameValid }"
        @click="createClient"
      >
        {{ $t('client.create') }}
      </BasePrimaryButton>
    </template>
  </BaseDialog>
</template>

<script lang="ts" setup>
type PresetSummary = {
  id: number;
  name: string;
  isDefault: boolean;
  mode: 'WIREGUARD' | 'SOCKS5';
};

const open = ref(false);
const name = ref<string>('');
const expiresAt = ref<string | null>(null);
const presetId = ref<number | null>(null);
const clientsStore = useClientsStore();

const { t } = useI18n();

defineProps<{ triggerClass?: string }>();

const { data: presets } = await useFetch<PresetSummary[]>(
  '/api/admin/obfuscator-presets',
  { method: 'get', default: () => [] }
);

const selectablePresets = computed(() =>
  (presets.value ?? []).filter((p) => !p.isDefault)
);

const existingNames = computed(
  () =>
    new Set(
      (clientsStore.clients ?? []).map((c) => normalizeClientName(c.name))
    )
);

const nameError = computed(() => {
  const value = name.value.trim();
  if (value.length === 0) {
    return null;
  }
  switch (validateClientName(value)) {
    case 'tooLong':
      return t('client.nameError.tooLong', { max: CLIENT_NAME_MAX_LENGTH });
    case 'invalidChars':
      return t('client.nameError.invalidChars');
  }
  if (existingNames.value.has(normalizeClientName(value))) {
    return t('client.nameError.duplicate');
  }
  return null;
});

const nameValid = computed(() => {
  const value = name.value.trim();
  return (
    value.length > 0 &&
    validateClientName(value) === null &&
    !existingNames.value.has(normalizeClientName(value))
  );
});

function createClient() {
  if (!nameValid.value) {
    return;
  }
  return _createClient({
    name: name.value.trim(),
    expiresAt: expiresAt.value,
    presetId: presetId.value,
  });
}

const _createClient = useSubmit(
  '/api/client',
  {
    method: 'post',
  },
  {
    revert: async (success) => {
      await clientsStore.refresh();
      if (success) {
        open.value = false;
        name.value = '';
        expiresAt.value = null;
        presetId.value = null;
      }
    },
    successMsg: t('client.created'),
  }
);
</script>
