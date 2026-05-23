<template>
  <BaseDialog :trigger-class="triggerClass">
    <template #trigger>
      <slot />
    </template>
    <template #title>
      {{ $t('client.config') }}
    </template>
    <template #description>
      <div v-if="status === 'success'">
        <BaseCodeBlock :code="config ?? ''" />
      </div>
      <div v-else>
        <span>{{ $t('general.loading') }}</span>
      </div>
    </template>
    <template #actions>
      <DialogClose as-child>
        <BaseSecondaryButton>{{ $t('dialog.cancel') }}</BaseSecondaryButton>
      </DialogClose>
      <DialogClose as-child>
        <BasePrimaryButton @click="copyCode">
          {{ $t('copy.copy') }}
        </BasePrimaryButton>
      </DialogClose>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
const props = defineProps<{ triggerClass?: string; clientId: number }>();

const toast = useToast();
const { t } = useI18n();
const copy = useCopyToClipboard();

const { data: config, status } = useFetch(
  `/api/client/${props.clientId}/config`,
  {
    responseType: 'text',
    server: false,
  }
);

async function copyCode() {
  if (status.value !== 'success') {
    return;
  }

  try {
    await copy(config.value ?? '');
    toast.showToast({ type: 'success', message: t('copy.copied') });
  } catch (e) {
    console.error('failed to copy config', e);
    toast.showToast({ type: 'error', message: t('copy.failed') });
  }
}
</script>
