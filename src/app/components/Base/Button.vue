<template>
  <component :is="as" role="button" :class="VARIANT_CLASSES[variant]">
    <slot />
  </component>
</template>

<script setup lang="ts">
const VARIANT_CLASSES = {
  primary:
    'inline-flex items-center rounded border-2 border-red-800 bg-red-800 px-4 py-2 text-white transition hover:border-red-600 hover:bg-red-600',
  secondary:
    'inline-flex items-center rounded border-2 border-gray-100 px-4 py-2 text-gray-700 transition hover:border-red-800 hover:bg-red-800 hover:text-white dark:border-neutral-600 dark:text-neutral-200',
} as const;

withDefaults(
  defineProps<{ as?: string; variant?: keyof typeof VARIANT_CLASSES }>(),
  { as: 'button', variant: 'secondary' }
);
</script>
