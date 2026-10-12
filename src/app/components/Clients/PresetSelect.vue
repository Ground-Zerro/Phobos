<template>
  <div class="flex flex-col gap-1">
    <FormLabel :for="id">{{ $t('client.preset') }}</FormLabel>
    <BaseSelect :id="id" v-model="presetId" :options="options" />
  </div>
</template>

<script setup lang="ts">
import type { ObfuscationMode } from '~~/shared/utils/obfuscation';

const props = defineProps<{
  id: string;
  presets: ReadonlyArray<{ id: number; name: string; mode: ObfuscationMode }>;
}>();

const presetId = defineModel<number | null>({ required: true });

const { t } = useI18n();

const options = computed(() => [
  { value: null, label: t('client.presetUseDefault') },
  ...props.presets.map((p) => ({
    value: p.id,
    label: `${p.name} (${p.mode === 'SOCKS5' ? 'SOCKS5' : 'WireGuard'})`,
  })),
]);
</script>
