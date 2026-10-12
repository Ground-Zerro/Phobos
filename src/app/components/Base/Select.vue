<template>
  <select
    v-model="model"
    class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
  >
    <option
      v-for="option in options"
      :key="String(option.value)"
      :value="option.value"
    >
      {{ option.label }}
    </option>
  </select>
</template>

<script setup lang="ts" generic="T">
defineProps<{
  options: ReadonlyArray<{ value: T; label: string }>;
}>();

const model = defineModel<T>();
</script>
