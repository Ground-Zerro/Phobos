<template>
  <div>
    <p class="text-center text-lg">
      {{ $t('setup.setupConfigDesc') }}
    </p>
    <div class="mt-8 flex flex-col gap-3">
      <div class="flex flex-col">
        <FormFieldHeader
          id="host"
          :label="$t('general.host')"
          :description="$t('setup.hostDesc')"
        />
        <BaseInput
          id="host"
          v-model.trim="host"
          name="host"
          type="text"
          class="w-full"
          placeholder="vpn.example.com"
        />
      </div>
      <div class="mt-4 flex justify-center">
        <BaseButton variant="primary" @click="submit">
          {{ $t('general.continue') }}
        </BaseButton>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({
  layout: 'setup',
});

const host = ref<string | null>(null);

const _submit = useSubmit(
  '/api/setup/3',
  {
    method: 'post',
  },
  {
    revert: async (success) => {
      if (success) {
        await navigateTo('/setup/4');
      }
    },
    noSuccessToast: true,
  }
);

function submit() {
  const value = host.value?.trim();
  return _submit({ host: value ? value : null });
}
</script>
