<template>
  <div
    :class="`absolute bottom-0 left-0 right-0 z-0 h-6 ${globalStore.uiChartType === 'line' && 'line-chart'}`"
  >
    <BaseChart
      :options="chartOptions('tx')"
      :series="client.transferTxSeries"
    />
  </div>
  <div
    :class="`absolute left-0 right-0 top-0 z-0 h-6 ${globalStore.uiChartType === 'line' && 'line-chart'}`"
  >
    <BaseChart
      :options="chartOptions('rx')"
      :series="client.transferRxSeries"
      style="transform: scaleY(-1)"
    />
  </div>
</template>

<script setup lang="ts">
import type { ApexOptions } from 'apexcharts';

defineProps<{
  client: LocalClient;
}>();

const globalStore = useGlobalStore();
const theme = useTheme();

const sharedOptions = computed(
  () =>
    ({
      chart: {
        type: globalStore.uiChartType,
        background: 'transparent',
        stacked: false,
        toolbar: { show: false },
        animations: { enabled: false },
        parentHeightOffset: 0,
        sparkline: { enabled: true },
      },
      stroke: {
        curve: 'smooth',
        width: UI_CHART_PROPS[globalStore.uiChartType].strokeWidth,
      },
      fill: {
        type: 'gradient',
        gradient: {
          shade: 'dark',
          type: 'vertical',
          shadeIntensity: 0,
          gradientToColors: CHART_COLORS.gradient[theme.value],
          inverseColors: false,
          opacityTo: 0,
          stops: [0, 100],
        },
      },
      dataLabels: { enabled: false },
      plotOptions: { bar: { horizontal: false } },
      xaxis: {
        labels: { show: false },
        axisTicks: { show: false },
        axisBorder: { show: false },
      },
      yaxis: { labels: { show: false }, min: 0 },
      tooltip: { enabled: false },
      legend: { show: false },
      grid: {
        show: false,
        padding: { left: -10, right: 0, bottom: -15, top: -15 },
        column: { opacity: 0 },
        xaxis: { lines: { show: false } },
      },
    }) satisfies ApexOptions
);

const colored = computed(() => ({
  tx: { ...sharedOptions.value, colors: [CHART_COLORS.tx[theme.value]] },
  rx: { ...sharedOptions.value, colors: [CHART_COLORS.rx[theme.value]] },
}));

function chartOptions(direction: 'tx' | 'rx') {
  return colored.value[direction];
}
</script>

<style scoped lang="css">
.line-chart .apexcharts-svg {
  transform: translateY(3px);
}
</style>
