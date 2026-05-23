<template>
  <div>
    <p class="text-center text-lg">
      {{ $t('setup.setupConfigDesc') }}
    </p>
    <div class="mt-8 flex flex-col gap-3">
      <div class="flex flex-col">
        <div class="flex items-center">
          <FormLabel for="host">{{ $t('general.host') }}</FormLabel>
          <BaseTooltip :text="$t('setup.hostDesc')">
            <IconsInfo class="size-4" />
          </BaseTooltip>
        </div>
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
        <BasePrimaryButton @click="submit">
          {{ $t('general.continue') }}
        </BasePrimaryButton>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({
  layout: 'setup',
});

const setupStore = useSetupStore();
setupStore.setStep(4);

const host = ref<string | null>(null);

const _submit = useSubmit(
  '/api/setup/4',
  {
    method: 'post',
  },
  {
    revert: async (success) => {
      if (success) {
        await navigateTo('/setup/5');
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
