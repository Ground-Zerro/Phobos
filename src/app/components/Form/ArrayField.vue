<template>
  <div class="flex flex-col gap-2">
    <div v-if="!data?.length">
      {{ data === null ? $t('form.nullNoItems') : $t('form.noItems') }}
    </div>
    <div v-for="(item, i) in data" v-else :key="i">
      <div class="mt-1 flex flex-row gap-1">
        <input
          :value="item"
          :name="name"
          type="text"
          class="rounded-lg border-2 border-gray-100 text-gray-500 focus:border-red-800 focus:outline-0 focus:ring-0 dark:border-neutral-800 dark:bg-neutral-700 dark:text-neutral-200 dark:placeholder:text-neutral-400"
          @input="update($event, i)"
        />
        <BaseButton type="button" class="rounded-lg" @click="remove(i)">
          {{ '-' }}
        </BaseButton>
      </div>
    </div>
    <div class="mt-2">
      <BaseButton
        variant="primary"
        type="button"
        class="rounded-lg"
        @click="add"
      >
        {{ $t('form.add') }}
      </BaseButton>
    </div>
  </div>
</template>

<script lang="ts" setup>
const props = defineProps<{ name: string; nullable?: boolean }>();
const data = defineModel<string[] | null>({ required: true });

function update(e: Event, i: number) {
  if (data.value) {
    data.value[i] = (e.target as HTMLInputElement).value;
  }
}

function add() {
  if (data.value === null) {
    data.value = [''];
  } else {
    data.value.push('');
  }
}

function remove(i: number) {
  if (!data.value) return;
  data.value.splice(i, 1);
  if (props.nullable && data.value.length === 0) {
    data.value = null;
  }
}
</script>
