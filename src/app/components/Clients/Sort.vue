<template>
  <BaseButton variant="primary" @click="toggleSort">
    <IconsArrowDown v-if="globalStore.sortClient === true" class="mr-2 w-4" />
    <IconsArrowUp v-else class="mr-2 w-4" />
    <span class="text-sm">{{ $t('client.sort') }}</span>
  </BaseButton>
</template>

<script setup lang="ts">
const globalStore = useGlobalStore();
const clientsStore = useClientsStore();

function toggleSort() {
  globalStore.sortClient = !globalStore.sortClient;
  clientsStore.resort();
}
</script>
