<template>
  <DialogRoot v-model:open="open" :modal="true">
    <DialogPortal>
      <DialogOverlay
        class="fixed inset-0 z-30 bg-gray-500 opacity-75 dark:bg-black dark:opacity-50"
      />
      <DialogContent
        class="fixed left-1/2 top-1/2 z-[100] flex max-h-[90vh] w-[90vw] max-w-2xl -translate-x-1/2 -translate-y-1/2 flex-col rounded-md bg-white p-6 shadow-2xl focus:outline-none dark:bg-neutral-700"
      >
        <DialogTitle
          class="m-0 text-lg font-semibold text-gray-900 dark:text-neutral-200"
        >
          {{ $t('admin.warp.importTitle') }}
        </DialogTitle>
        <DialogDescription
          class="mb-4 mt-2 text-sm leading-normal text-gray-500 dark:text-neutral-300"
        >
          {{ $t('admin.warp.importDesc') }}
        </DialogDescription>

        <BaseTextArea
          v-model="configText"
          class="h-72 w-full resize-none font-mono text-xs"
          :disabled="loading || fetching"
        />

        <p v-if="errorMsg" class="mt-2 text-sm text-red-600 dark:text-red-400">
          {{ errorMsg }}
        </p>

        <div class="mt-4 flex flex-wrap justify-end gap-2">
          <DialogClose as-child>
            <BaseSecondaryButton :disabled="loading" @click="onCancel">
              {{ $t('dialog.cancel') }}
            </BaseSecondaryButton>
          </DialogClose>
          <BasePrimaryButton
            :disabled="loading || fetching || !configText.trim()"
            @click="apply"
          >
            {{ loading ? $t('general.loading') : $t('admin.warp.importApply') }}
          </BasePrimaryButton>
        </div>
      </DialogContent>
    </DialogPortal>
  </DialogRoot>
</template>

<script setup lang="ts">
const emit = defineEmits<{ success: [] }>();

const { t } = useI18n();
const toast = useToast();

const open = defineModel<boolean>('open', { default: false });
const configText = ref('');
const loading = ref(false);
const fetching = ref(false);
const errorMsg = ref('');

async function loadCurrentConfig() {
  fetching.value = true;
  try {
    const text = await $fetch<string>('/api/admin/warp/export', {
      responseType: 'text',
    });
    configText.value = typeof text === 'string' ? text : String(text ?? '');
  } catch {
    configText.value = '';
  } finally {
    fetching.value = false;
  }
}

watch(open, (isOpen) => {
  if (isOpen) {
    errorMsg.value = '';
    loadCurrentConfig();
  } else {
    configText.value = '';
    errorMsg.value = '';
  }
});

function onCancel() {
  open.value = false;
}

async function apply() {
  errorMsg.value = '';
  loading.value = true;
  try {
    await $fetch('/api/admin/warp/import', {
      method: 'post',
      body: { config: configText.value },
    });
    open.value = false;
    toast.showToast({
      type: 'success',
      message: t('admin.warp.importSuccess'),
    });
    emit('success');
  } catch (e: unknown) {
    const msg =
      e instanceof Error
        ? e.message
        : ((e as { data?: { message?: string } })?.data?.message ??
          t('general.error'));
    errorMsg.value = msg;
  } finally {
    loading.value = false;
  }
}
</script>
