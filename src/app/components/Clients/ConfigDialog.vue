<template>
  <BaseDialog v-model:open="open" :trigger-class="triggerClass">
    <template #trigger>
      <slot />
    </template>
    <template #title>
      {{ $t('client.config') }}
    </template>
    <template #description>
      <div v-if="config">
        <p
          v-if="hasSocks5"
          class="mb-2 text-xs text-gray-500 dark:text-neutral-400"
        >
          {{ $t('client.socks5ConfigNote') }}
        </p>
        <BaseCodeBlock :code="config" />
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
const props = defineProps<{
  triggerClass?: string;
  clientId: number;
  hasSocks5?: boolean;
}>();

const toast = useToast();
const { t } = useI18n();
const copy = useCopyToClipboard();

const open = ref(false);
const config = ref<string | null>(null);
const loading = ref(false);

async function loadConfig() {
  if (config.value || loading.value) return;
  loading.value = true;
  try {
    const text = await $fetch<string>(`/api/client/${props.clientId}/config`, {
      responseType: 'text',
    });
    config.value = typeof text === 'string' ? text : String(text ?? '');
  } catch (e) {
    console.error('failed to fetch config', e);
  } finally {
    loading.value = false;
  }
}

watch(open, (isOpen) => {
  if (isOpen) {
    loadConfig();
  }
});

async function copyCode() {
  const text = config.value;
  if (!text) {
    toast.showToast({ type: 'error', message: t('copy.failed') });
    return;
  }
  try {
    await copy(text);
    toast.showToast({ type: 'success', message: t('copy.copied') });
  } catch (e) {
    console.error('failed to copy config', e);
    toast.showToast({ type: 'error', message: t('copy.failed') });
  }
}
</script>
