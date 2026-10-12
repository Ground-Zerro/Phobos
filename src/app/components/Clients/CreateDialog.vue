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
        <ClientsPresetSelect
          id="presetId"
          v-model="presetId"
          :presets="selectable"
        />
      </div>
    </template>
    <template #actions>
      <DialogClose as-child>
        <BaseButton>{{ $t('dialog.cancel') }}</BaseButton>
      </DialogClose>
      <BaseButton
        variant="primary"
        :disabled="!nameValid"
        :class="{ 'cursor-not-allowed opacity-50': !nameValid }"
        @click="createClient"
      >
        {{ $t('client.create') }}
      </BaseButton>
    </template>
  </BaseDialog>
</template>

<script lang="ts" setup>
const open = ref(false);
const name = ref<string>('');
const expiresAt = ref<string | null>(null);
const presetId = ref<number | null>(null);
const clientsStore = useClientsStore();

const { t } = useI18n();

defineProps<{ triggerClass?: string }>();

const { selectable } = await usePresetSummaries();

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

const nameValid = computed(
  () => name.value.trim().length > 0 && nameError.value === null
);

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
