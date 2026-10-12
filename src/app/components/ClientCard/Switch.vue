<template>
  <BaseSwitch
    v-model="enabled"
    :title="
      client.enabled ? $t('client.disableClient') : $t('client.enableClient')
    "
    @click="toggleClient(undefined)"
  />
</template>

<script setup lang="ts">
const props = defineProps<{
  client: LocalClient;
}>();

const enabled = ref(props.client.enabled);

const clientsStore = useClientsStore();

const toggleClient = useSubmit(
  () =>
    `/api/client/${props.client.id}/${props.client.enabled ? 'disable' : 'enable'}`,
  { method: 'post' },
  {
    revert: () => clientsStore.refresh(),
    noSuccessToast: true,
  }
);
</script>
