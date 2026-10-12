<template>
  <FormFieldHeader :id="id" :label="label" :description="description" />
  <BaseInput
    :id="id"
    v-model.trim="data"
    :name="id"
    type="password"
    :autocomplete="autocomplete"
    :placeholder="placeholder"
  />
</template>

<script lang="ts" setup>
defineProps<{
  id: string;
  label: string;
  autocomplete: string;
  description?: string;
  placeholder?: string;
}>();

const data = defineModel<string>();
</script>
