import type { ObfuscationMode } from '~~/shared/utils/obfuscation';

export async function usePresetSummaries() {
  const { data } = await useFetch('/api/obfuscator-presets', {
    method: 'get',
    default: () => [],
  });

  const selectable = computed(() => data.value.filter((p) => !p.isDefault));

  function modeOf(presetId: number | null): ObfuscationMode | undefined {
    return (
      presetId === null
        ? data.value.find((p) => p.isDefault)
        : data.value.find((p) => p.id === presetId)
    )?.mode;
  }

  return { selectable, modeOf };
}
