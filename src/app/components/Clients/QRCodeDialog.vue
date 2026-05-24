<template>
  <BaseDialog v-model:open="open">
    <template #trigger>
      <slot />
    </template>
    <template #description>
      <div class="bg-white">
        <img
          ref="img"
          :src="qrCode"
          class="cursor-pointer"
          :title="$t('copy.copyConfig')"
          @click="copyConfig"
        />
      </div>
    </template>
    <template #actions>
      <BaseSecondaryButton
        class="flex items-center gap-2"
        :title="$t('client.copyLink')"
        @click="copyLink"
      >
        <IconsLink class="size-5" /> {{ $t('client.linkShort') }}
      </BaseSecondaryButton>
      <BaseSecondaryButton
        class="flex items-center gap-2"
        :title="$t('client.downloadPng')"
        @click="downloadPng"
      >
        <IconsDownload class="size-5" /> PNG
      </BaseSecondaryButton>
      <DialogClose as-child>
        <BaseSecondaryButton>{{ $t('dialog.cancel') }}</BaseSecondaryButton>
      </DialogClose>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
const props = defineProps<{
  qrCode: string;
  configUrl: string;
  clientName?: string | null;
}>();

const toast = useToast();
const { t } = useI18n();
const img = useTemplateRef('img');
const copy = useCopyToClipboard();

const open = ref(false);
const configText = ref<string | null>(null);
const configLoading = ref(false);

async function loadConfig() {
  if (configText.value || configLoading.value) return;
  configLoading.value = true;
  try {
    const text = await $fetch<string>(props.configUrl, {
      responseType: 'text',
    });
    configText.value = typeof text === 'string' ? text : String(text ?? '');
  } catch (e) {
    console.error('failed to fetch config', e);
  } finally {
    configLoading.value = false;
  }
}

watch(open, (isOpen) => {
  if (isOpen) {
    loadConfig();
  }
});

async function copyConfig() {
  const text = configText.value;
  if (!text) {
    if (!configLoading.value) {
      loadConfig();
    }
    toast.showToast({ type: 'error', message: t('copy.failed') });
    return;
  }
  try {
    await copy(text);
    toast.showToast({ type: 'success', message: t('copy.copied') });
  } catch (e) {
    console.error('failed to copy config', e);
    toast.showToast({ type: 'error', message: t('copy.failed') });
  }
}

async function svgToPng() {
  if (!img.value || !img.value.complete || img.value.naturalWidth === 0) {
    throw new Error('image is not loaded');
  }

  const width = 1000;
  const height = 1000;

  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    throw new Error('was not able to create 2d context');
  }
  ctx.drawImage(img.value!, 0, 0, width, height);

  return new Promise<Blob>((res, rej) => {
    canvas.toBlob((blob) => {
      if (!blob) {
        return rej(new Error('was not able to create blob'));
      }
      return res(blob);
    }, 'image/png');
  });
}

async function copyLink() {
  const config = configText.value;
  if (!config) {
    if (!configLoading.value) loadConfig();
    toast.showToast({ type: 'error', message: t('client.linkFailed') });
    return;
  }
  try {
    const link = buildPhobosLink(config, props.clientName ?? null);
    await copy(link);
    toast.showToast({ type: 'success', message: t('client.linkCopied') });
  } catch (e) {
    console.error('failed to copy phobos link', e);
    toast.showToast({ type: 'error', message: t('client.linkFailed') });
  }
}

async function downloadPng() {
  try {
    const blob = await svgToPng();

    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'client-config.png';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  } catch (e) {
    console.error('failed to download png', e);
    toast.showToast({ type: 'error', message: t('toast.unknown') });
  }
}
</script>
