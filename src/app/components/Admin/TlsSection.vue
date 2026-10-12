<template>
  <FormGroup>
    <FormHeading :description="$t('admin.tls.desc')">
      {{ $t('admin.tls.title') }}
    </FormHeading>

    <div
      v-if="status === 'pending'"
      class="text-sm text-gray-500 dark:text-neutral-400"
    >
      {{ $t('general.loading') }}
    </div>

    <div v-else-if="state" class="flex flex-col gap-3">
      <div
        class="rounded-lg border border-gray-100 bg-gray-50 px-4 py-3 text-sm dark:border-neutral-700 dark:bg-neutral-800"
      >
        <span class="font-medium text-gray-700 dark:text-neutral-200"
          >{{ $t('admin.tls.current') }}:</span
        >
        <span class="ml-2 text-gray-600 dark:text-neutral-300">{{
          $t(`admin.tls.origin.${state.origin}`)
        }}</span>
      </div>

      <TlsModeForm
        ref="form"
        :submitting="submitting"
        :submit-label="() => $t('admin.tls.apply')"
        @submit="apply"
      />
    </div>
  </FormGroup>
</template>

<script setup lang="ts">
const { t } = useI18n();
const toast = useToast();
const form = useTemplateRef('form');
const submitting = ref(false);

const {
  data: state,
  status,
  refresh,
} = await useFetch('/api/admin/tls', { method: 'get' });

async function apply(body: Record<string, string>) {
  submitting.value = true;
  try {
    const result = await $fetch('/api/admin/tls', { method: 'post', body });
    toast.showToast({
      type: 'success',
      message: result.httpsUrl
        ? t('admin.tls.appliedRestart', { url: result.httpsUrl })
        : t('admin.tls.applied'),
    });
    form.value?.reset();
    await refresh();
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
