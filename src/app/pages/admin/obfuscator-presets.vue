<template>
  <main class="flex flex-col gap-4">
    <p class="whitespace-pre-line text-sm text-gray-600 dark:text-neutral-300">
      {{ $t('admin.obfuscatorPresets.desc') }}
    </p>

    <div class="flex justify-end">
      <BaseDialog v-model:open="createOpen">
        <template #trigger>
          <BasePrimaryButton>{{ $t('admin.obfuscatorPresets.add') }}</BasePrimaryButton>
        </template>
        <template #title>
          {{ $t('admin.obfuscatorPresets.add') }}
        </template>
        <template #description>
          <div class="flex flex-col gap-3">
            <div class="flex flex-col gap-1">
              <label class="text-sm">{{ $t('admin.obfuscatorPresets.nameLabel') }}</label>
              <BaseInput v-model.trim="newPreset.name" type="text" placeholder="custom" />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm">{{ $t('admin.obfuscatorPresets.extPortLabel') }}</label>
              <BaseInput v-model.number="newPreset.extPort" type="number" :placeholder="`${PORT_MIN}-${PORT_MAX} (auto if empty)`" />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm">{{ $t('admin.obfuscatorPresets.maskingLabel') }}</label>
              <select
                v-model="newPreset.masking"
                class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
              >
                <option value="STUN">STUN</option>
                <option value="MEDIA">MEDIA</option>
                <option value="AUTO">AUTO</option>
                <option value="NONE">NONE</option>
              </select>
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm">{{ $t('admin.obfuscatorPresets.idleLabel') }}</label>
              <BaseInput v-model.number="newPreset.idle" type="number" placeholder="300" />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm">{{ $t('admin.obfuscatorPresets.dummyLabel') }}</label>
              <BaseInput v-model.number="newPreset.dummy" type="number" placeholder="40" />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm">{{ $t('admin.obfuscatorPresets.clientLocalPortLabel') }}</label>
              <BaseInput v-model.number="newPreset.clientWgLocalPort" type="number" placeholder="13255" />
            </div>
          </div>
        </template>
        <template #actions>
          <DialogClose as-child>
            <BaseSecondaryButton>{{ $t('dialog.cancel') }}</BaseSecondaryButton>
          </DialogClose>
          <BasePrimaryButton :disabled="!canCreate || creating" @click="create">
            {{ $t('dialog.create') }}
          </BasePrimaryButton>
        </template>
      </BaseDialog>
    </div>

    <div v-if="presets" class="flex flex-col gap-4">
      <div
        v-for="p in presets"
        :key="p.id"
        class="rounded-lg border-2 border-gray-100 p-4 dark:border-neutral-700"
        :class="p.isDefault ? 'border-red-200 dark:border-red-900' : ''"
      >
        <div class="mb-3 flex items-center justify-between">
          <h3 class="text-lg font-medium">
            {{ p.name }}
            <span v-if="p.isDefault" class="ml-2 rounded bg-red-800 px-2 py-0.5 text-xs text-white">
              {{ $t('admin.obfuscatorPresets.default') }}
            </span>
          </h3>
          <span class="text-xs text-gray-500 dark:text-neutral-400">
            {{ $t('admin.obfuscatorPresets.clientCount', { n: p.clientCount }) }}
          </span>
        </div>

        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div class="flex flex-col gap-1">
            <label class="text-sm">{{ $t('admin.obfuscatorPresets.nameLabel') }}</label>
            <BaseInput v-model.trim="p.name" type="text" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm">{{ $t('admin.obfuscatorPresets.extPortLabel') }}</label>
            <div class="flex gap-2">
              <BaseInput v-model.number="p.extPort" type="number" class="flex-1" />
              <BaseSecondaryButton @click="regeneratePort(p.id)">
                {{ $t('admin.obfuscatorPresets.regeneratePort') }}
              </BaseSecondaryButton>
            </div>
          </div>
          <div class="flex flex-col gap-1 sm:col-span-2">
            <label class="text-sm">{{ $t('admin.obfuscatorPresets.keyLabel') }}</label>
            <div class="flex gap-2">
              <BaseInput v-model.trim="p.key" type="text" class="flex-1 font-mono text-xs" />
              <BaseSecondaryButton @click="regenerateKey(p.id)">
                {{ $t('admin.obfuscatorPresets.regenerateKey') }}
              </BaseSecondaryButton>
            </div>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm">{{ $t('admin.obfuscatorPresets.maskingLabel') }}</label>
            <select
              v-model="p.masking"
              class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
            >
              <option value="STUN">STUN</option>
              <option value="MEDIA">MEDIA</option>
              <option value="AUTO">AUTO</option>
              <option value="NONE">NONE</option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm">{{ $t('admin.obfuscatorPresets.idleLabel') }}</label>
            <BaseInput v-model.number="p.idle" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm">{{ $t('admin.obfuscatorPresets.dummyLabel') }}</label>
            <BaseInput v-model.number="p.dummy" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm">{{ $t('admin.obfuscatorPresets.clientLocalPortLabel') }}</label>
            <BaseInput v-model.number="p.clientWgLocalPort" type="number" />
          </div>
        </div>

        <div class="mt-4 flex flex-wrap items-center gap-2">
          <BasePrimaryButton @click="save(p)">
            {{ $t('form.save') }}
          </BasePrimaryButton>
          <BaseSecondaryButton v-if="!p.isDefault" @click="setDefault(p.id)">
            {{ $t('admin.obfuscatorPresets.setAsDefault') }}
          </BaseSecondaryButton>
          <BaseSecondaryButton
            v-if="!p.isDefault"
            class="text-red-700 dark:text-red-400"
            @click="remove(p.id)"
          >
            {{ $t('dialog.delete') }}
          </BaseSecondaryButton>
        </div>
      </div>
    </div>

    <div v-else class="text-sm text-gray-500">{{ $t('general.loading') }}</div>
  </main>
</template>

<script setup lang="ts">
type Masking = 'STUN' | 'MEDIA' | 'AUTO' | 'NONE';
type Preset = {
  id: number;
  name: string;
  isDefault: boolean;
  extPort: number;
  key: string;
  masking: Masking;
  idle: number;
  dummy: number;
  clientWgLocalPort: number;
  clientCount: number;
};

const { t } = useI18n();
const toast = useToast();

const PORT_MIN = 51822;
const PORT_MAX = 51921;

const { data: presets, refresh } = await useFetch<Preset[]>(
  '/api/admin/obfuscator-presets',
  { method: 'get' }
);

const createOpen = ref(false);
const creating = ref(false);
const newPreset = ref<{
  name: string;
  extPort: number | null;
  masking: Masking;
  idle: number;
  dummy: number;
  clientWgLocalPort: number;
}>({
  name: '',
  extPort: null,
  masking: 'STUN',
  idle: 300,
  dummy: 40,
  clientWgLocalPort: 13255,
});

const canCreate = computed(() => newPreset.value.name.trim().length > 0);

async function create() {
  if (!canCreate.value) return;
  creating.value = true;
  try {
    const body: Record<string, unknown> = {
      name: newPreset.value.name.trim(),
      masking: newPreset.value.masking,
      idle: newPreset.value.idle,
      dummy: newPreset.value.dummy,
      clientWgLocalPort: newPreset.value.clientWgLocalPort,
    };
    if (newPreset.value.extPort) body.extPort = newPreset.value.extPort;

    await $fetch('/api/admin/obfuscator-presets', { method: 'post', body });
    await refresh();
    createOpen.value = false;
    newPreset.value = {
      name: '',
      extPort: null,
      masking: 'STUN',
      idle: 300,
      dummy: 40,
      clientWgLocalPort: 13255,
    };
    toast.showToast({ type: 'success', message: t('toast.saved') });
  } catch (e) {
    toast.showToast({ type: 'error', message: extractMessage(e) });
  } finally {
    creating.value = false;
  }
}

async function save(p: Preset) {
  try {
    await $fetch(`/api/admin/obfuscator-presets/${p.id}`, {
      method: 'post',
      body: {
        name: p.name,
        extPort: p.extPort,
        key: p.key,
        masking: p.masking,
        idle: p.idle,
        dummy: p.dummy,
        clientWgLocalPort: p.clientWgLocalPort,
      },
    });
    toast.showToast({ type: 'success', message: t('toast.saved') });
    await refresh();
  } catch (e) {
    toast.showToast({ type: 'error', message: extractMessage(e) });
  }
}

async function remove(id: number) {
  if (!confirm(t('admin.obfuscatorPresets.deleteConfirm'))) return;
  try {
    await $fetch(`/api/admin/obfuscator-presets/${id}`, { method: 'delete' });
    await refresh();
    toast.showToast({ type: 'success', message: t('toast.saved') });
  } catch (e) {
    toast.showToast({ type: 'error', message: extractMessage(e) });
  }
}

async function setDefault(id: number) {
  try {
    await $fetch(`/api/admin/obfuscator-presets/${id}/set-default`, {
      method: 'post',
    });
    await refresh();
    toast.showToast({ type: 'success', message: t('toast.saved') });
  } catch (e) {
    toast.showToast({ type: 'error', message: extractMessage(e) });
  }
}

async function regenerateKey(id: number) {
  try {
    await $fetch(`/api/admin/obfuscator-presets/${id}/regenerate-key`, {
      method: 'post',
    });
    await refresh();
    toast.showToast({ type: 'success', message: t('toast.saved') });
  } catch (e) {
    toast.showToast({ type: 'error', message: extractMessage(e) });
  }
}

async function regeneratePort(id: number) {
  try {
    await $fetch(`/api/admin/obfuscator-presets/${id}/regenerate-port`, {
      method: 'post',
    });
    await refresh();
    toast.showToast({ type: 'success', message: t('toast.saved') });
  } catch (e) {
    toast.showToast({ type: 'error', message: extractMessage(e) });
  }
}

function extractMessage(e: unknown): string {
  if (e && typeof e === 'object' && 'data' in e) {
    const d = (e as { data?: { message?: string } }).data;
    if (d?.message) return d.message;
  }
  return t('toast.unknown');
}
</script>
