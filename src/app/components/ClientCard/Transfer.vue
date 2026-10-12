<template>
  <template v-for="row in rows" :key="row.title">
    <div v-if="row.total" class="min-w-20 md:min-w-24">
      <span class="flex gap-1" :title="$t(row.title) + bytes(row.total)">
        <component :is="row.icon" class="mt-0.5 inline h-3 align-middle" />
        <div>
          <span class="text-gray-700 dark:text-neutral-200"
            >{{ bytes(row.current) }}/s</span
          >
          <br /><span class="font-regular" style="font-size: 0.85em">{{
            bytes(row.total)
          }}</span>
        </div>
      </span>
    </div>
  </template>
</template>

<script setup lang="ts">
import { IconsArrowDown, IconsArrowUp } from '#components';

const props = defineProps<{
  client: LocalClient;
}>();

const rows = computed(() => [
  {
    title: 'client.totalDownload',
    icon: IconsArrowDown,
    total: props.client.transferTx,
    current: props.client.transferTxCurrent,
  },
  {
    title: 'client.totalUpload',
    icon: IconsArrowUp,
    total: props.client.transferRx,
    current: props.client.transferRxCurrent,
  },
]);
</script>
