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
        <BaseButton>{{ $t('dialog.cancel') }}</BaseButton>
      </DialogClose>
      <DialogClose as-child>
        <BaseButton variant="primary" @click="copyCode">
          {{ $t('copy.copy') }}
        </BaseButton>
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

const { t } = useI18n();
const { open, config, copyText } = useClientConfig(
  () => `/api/client/${props.clientId}/config`
);

function copyCode() {
  return copyText(config.value, {
    success: t('copy.copied'),
    failure: t('copy.failed'),
  });
}
</script>
