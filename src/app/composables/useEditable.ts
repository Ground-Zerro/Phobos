export function useEditable<T>(source: {
  data: Ref<T>;
  refresh: () => Promise<void>;
}) {
  const data = ref(source.data.value) as Ref<T>;

  async function revert() {
    await source.refresh();
    data.value = source.data.value;
  }

  return { data, revert };
}
