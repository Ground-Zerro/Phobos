<template>
  <ClientCardCharts :client="client" />
  <div
    class="relative flex flex-col justify-between gap-3 px-3 py-3 sm:flex-row md:py-5"
  >
    <div class="flex w-full items-center gap-3 md:gap-4">
      <ClientCardAvatar :client="client" />
      <div class="flex w-full flex-col gap-2 xxs:flex-row">
        <div class="flex flex-grow flex-col gap-1">
          <div class="flex items-center gap-2">
            <ClientCardName :client="client" />
            <span
              class="rounded px-1.5 py-0.5 text-[10px] font-medium"
              :class="
                isSocks5
                  ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300'
                  : 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300'
              "
              :title="$t('client.protocol')"
            >
              {{ isSocks5 ? 'SOCKS5' : 'WireGuard' }}
            </span>
            <span
              class="rounded bg-gray-100 px-1.5 py-0.5 text-[10px] font-medium text-gray-600 dark:bg-neutral-700/60 dark:text-neutral-300"
              :title="$t('client.preset')"
            >
              {{ client.preset.name }}
            </span>
          </div>
          <div
            class="flex flex-col text-xs text-gray-500 dark:text-neutral-400"
          >
            <div>
              <ClientCardAddress :client="client" />
            </div>
            <div>
              <ClientCardLastSeen :client="client" />
            </div>
          </div>
          <ClientCardExpireDate :client="client" />
        </div>

        <div
          class="mt-px flex shrink-0 items-center justify-end gap-2 text-xs text-gray-400 dark:text-neutral-400"
        >
          <ClientCardTransfer :client="client" />
        </div>
      </div>
    </div>

    <div class="flex items-center justify-end">
      <div
        class="flex items-center justify-between gap-1 text-gray-400 dark:text-neutral-400"
      >
        <ClientCardSwitch :client="client" />
        <ClientCardEdit :client="client" />
        <ClientCardQRCode :client="client" />
        <ClientCardConfig :client="client" />
        <ClientCardInstallLinkBtn :client="client" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  client: LocalClient;
}>();

const isSocks5 = computed(() => props.client.preset.mode === 'SOCKS5');
</script>
