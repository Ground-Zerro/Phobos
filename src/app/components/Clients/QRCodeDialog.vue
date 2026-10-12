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
      <BaseButton
        class="flex items-center gap-2"
        :title="$t('client.copyLink')"
        @click="copyLink"
      >
        <IconsLink class="size-5" /> {{ $t('client.linkShort') }}
      </BaseButton>
      <BaseButton
        class="flex items-center gap-2"
        :title="$t('client.downloadPng')"
        @click="downloadPng"
      >
        <IconsDownload class="size-5" /> PNG
      </BaseButton>
      <DialogClose as-child>
        <BaseButton>{{ $t('dialog.cancel') }}</BaseButton>
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
const { open, config, copyText } = useClientConfig(() => props.configUrl);

function copyConfig() {
  return copyText(config.value, {
    success: t('copy.copied'),
    failure: t('copy.failed'),
  });
}

function copyLink() {
  return copyText(
    config.value && buildPhobosLink(config.value, props.clientName ?? null),
    { success: t('client.linkCopied'), failure: t('client.linkFailed') }
  );
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
