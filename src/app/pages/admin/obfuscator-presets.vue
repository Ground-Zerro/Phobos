<template>
  <main class="flex flex-col gap-4">
    <p class="whitespace-pre-line text-sm text-gray-600 dark:text-neutral-300">
      {{ $t('admin.obfuscatorPresets.desc') }}
    </p>

    <div class="flex justify-end">
      <BaseDialog v-model:open="createOpen">
        <template #trigger>
          <BasePrimaryButton>{{
            $t('admin.obfuscatorPresets.add')
          }}</BasePrimaryButton>
        </template>
        <template #title>
          {{ $t('admin.obfuscatorPresets.add') }}
        </template>
        <template #description>
          <div class="flex flex-col gap-3">
            <p class="text-sm text-gray-600 dark:text-neutral-300">
              {{ $t('admin.obfuscatorPresets.addDesc') }}
            </p>
            <div class="flex flex-col gap-1">
              <FormFieldLabel
                :label="$t('admin.obfuscatorPresets.nameLabel')"
                :hint="$t('admin.obfuscatorPresets.nameDesc')"
              />
              <BaseInput
                v-model.trim="newPreset.name"
                type="text"
                placeholder="custom"
              />
            </div>
            <div class="flex flex-col gap-1">
              <FormFieldLabel
                :label="$t('admin.obfuscatorPresets.modeLabel')"
                :hint="$t('admin.obfuscatorPresets.modeDesc')"
              />
              <select
                v-model="newPreset.mode"
                class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
              >
                <option value="WIREGUARD">WireGuard</option>
                <option value="SOCKS5">SOCKS5</option>
              </select>
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
            <span
              v-if="p.isDefault"
              class="ml-2 rounded bg-red-800 px-2 py-0.5 text-xs text-white"
            >
              {{ $t('admin.obfuscatorPresets.default') }}
            </span>
          </h3>
          <span class="text-xs text-gray-500 dark:text-neutral-400">
            {{
              $t('admin.obfuscatorPresets.clientCount', { n: p.clientCount })
            }}
          </span>
        </div>

        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div class="flex flex-col gap-1">
            <FormFieldLabel
              :label="$t('admin.obfuscatorPresets.nameLabel')"
              :hint="$t('admin.obfuscatorPresets.nameDesc')"
            />
            <BaseInput v-model.trim="p.name" type="text" />
          </div>
          <div class="flex flex-col gap-1">
            <FormFieldLabel
              :label="$t('admin.obfuscatorPresets.modeLabel')"
              :hint="$t('admin.obfuscatorPresets.modeDesc')"
            />
            <select
              v-model="p.mode"
              class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
            >
              <option value="WIREGUARD">WireGuard</option>
              <option value="SOCKS5">SOCKS5</option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <FormFieldLabel
              :label="
                $t(
                  p.mode === 'SOCKS5'
                    ? 'admin.obfuscatorPresets.sourceLportLabelSocks5'
                    : 'admin.obfuscatorPresets.sourceLportLabel'
                )
              "
              :hint="
                $t(
                  p.mode === 'SOCKS5'
                    ? 'admin.obfuscatorPresets.sourceLportDescSocks5'
                    : 'admin.obfuscatorPresets.sourceLportDesc'
                )
              "
            />
            <div class="flex gap-2">
              <BaseInput
                v-model.number="p.extPort"
                type="number"
                class="flex-1"
              />
              <BaseSecondaryButton @click="regeneratePort(p.id)">
                {{ $t('admin.obfuscatorPresets.regeneratePort') }}
              </BaseSecondaryButton>
            </div>
          </div>
          <div v-if="p.mode === 'WIREGUARD'" class="flex flex-col gap-1">
            <FormFieldLabel
              :label="$t('admin.obfuscatorPresets.targetLabel')"
              :hint="$t('admin.obfuscatorPresets.targetDesc')"
            />
            <BaseInput
              v-model.trim="p.target"
              type="text"
              :placeholder="$t('admin.obfuscatorPresets.targetPlaceholder')"
            />
          </div>
          <div class="flex flex-col gap-1">
            <FormFieldLabel
              :label="$t('admin.obfuscatorPresets.sourceIfLabel')"
              :hint="$t('admin.obfuscatorPresets.sourceIfDesc')"
            />
            <BaseInput
              v-model.trim="p.sourceIf"
              type="text"
              placeholder="0.0.0.0"
            />
          </div>
          <div class="flex flex-col gap-1 sm:col-span-2">
            <FormFieldLabel
              :label="$t('admin.obfuscatorPresets.keyLabel')"
              :hint="$t('admin.obfuscatorPresets.keyDesc')"
            />
            <div class="flex gap-2">
              <BaseInput
                v-model.trim="p.key"
                type="text"
                class="flex-1 font-mono text-xs"
              />
              <BaseSecondaryButton @click="regenerateKey(p.id)">
                {{ $t('admin.obfuscatorPresets.regenerateKey') }}
              </BaseSecondaryButton>
            </div>
          </div>
          <div class="flex flex-col gap-1">
            <FormFieldLabel
              :label="$t('admin.obfuscatorPresets.maskingLabel')"
              :hint="
                $t(
                  p.mode === 'SOCKS5'
                    ? 'admin.obfuscatorPresets.maskingDescSocks5'
                    : 'admin.obfuscatorPresets.maskingDesc'
                )
              "
            />
            <select
              v-model="p.masking"
              class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
              @change="onMaskingChange(p)"
            >
              <option value="STUN">STUN</option>
              <option value="MEDIA">MEDIA</option>
              <option v-if="p.mode === 'WIREGUARD'" value="AUTO">AUTO</option>
              <option v-if="p.mode === 'SOCKS5'" value="TLS">TLS</option>
              <option value="NONE">NONE</option>
            </select>
          </div>
          <div v-if="p.mode === 'SOCKS5'" class="flex flex-col gap-1">
            <FormFieldLabel
              :label="$t('admin.obfuscatorPresets.mediaSsrcLabel')"
              :hint="$t('admin.obfuscatorPresets.mediaSsrcDesc')"
            />
            <BaseInput
              v-model.number="p.mediaSsrc"
              type="number"
              min="0"
              :disabled="mediaSsrcDisabled(p)"
              :class="mediaSsrcDisabled(p) ? 'opacity-50' : ''"
            />
            <span
              v-if="mediaSsrcDisabled(p)"
              class="text-xs text-gray-500 dark:text-neutral-400"
            >
              {{ $t('admin.obfuscatorPresets.mediaSsrcDisabledNote') }}
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <FormFieldLabel
              :label="$t('admin.obfuscatorPresets.verboseLabel')"
              :hint="$t('admin.obfuscatorPresets.verboseDesc')"
            />
            <select
              v-model="p.verbose"
              class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
            >
              <option value="error">error</option>
              <option value="warn">warn</option>
              <option value="info">info</option>
              <option value="debug">debug</option>
              <option value="trace">trace</option>
            </select>
          </div>
          <template v-if="p.mode === 'WIREGUARD'">
            <div class="flex flex-col gap-1">
              <FormFieldLabel
                :label="$t('admin.obfuscatorPresets.obfuscateBytesLabel')"
                :hint="$t('admin.obfuscatorPresets.obfuscateBytesDesc')"
              />
              <BaseInput
                v-model.number="p.obfuscateBytes"
                type="number"
                min="0"
              />
            </div>
            <div class="flex flex-col gap-1">
              <FormFieldLabel
                :label="$t('admin.obfuscatorPresets.dummyLabel')"
                :hint="$t('admin.obfuscatorPresets.dummyDesc')"
              />
              <BaseInput
                v-model.number="p.dummy"
                type="number"
                min="0"
                :disabled="dummyDisabled(p)"
                :class="dummyDisabled(p) ? 'opacity-50' : ''"
              />
              <span
                v-if="dummyDisabled(p)"
                class="text-xs text-gray-500 dark:text-neutral-400"
              >
                {{ $t('admin.obfuscatorPresets.dummyDisabledNote') }}
              </span>
            </div>
            <div class="flex flex-col gap-1">
              <FormFieldLabel
                :label="$t('admin.obfuscatorPresets.clientLocalPortLabel')"
                :hint="$t('admin.obfuscatorPresets.clientLocalPortDesc')"
              />
              <BaseInput v-model.number="p.clientWgLocalPort" type="number" />
            </div>
          </template>
          <div v-else class="flex flex-col gap-1">
            <FormFieldLabel
              :label="$t('admin.obfuscatorPresets.clientLocalPortSocks5Label')"
              :hint="$t('admin.obfuscatorPresets.clientLocalPortSocks5Desc')"
            />
            <BaseInput v-model.number="p.clientLocalPort" type="number" />
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
type Mode = 'WIREGUARD' | 'SOCKS5';
type Masking = 'STUN' | 'MEDIA' | 'AUTO' | 'NONE' | 'TLS';
type Verbose = 'error' | 'warn' | 'info' | 'debug' | 'trace';
type Preset = {
  id: number;
  name: string;
  isDefault: boolean;
  mode: Mode;
  extPort: number;
  sourceIf: string;
  target: string | null;
  key: string;
  masking: Masking;
  obfuscateBytes: number;
  dummy: number;
  verbose: Verbose;
  clientWgLocalPort: number;
  mediaSsrc: number | null;
  clientLocalPort: number;
  clientCount: number;
};

const { t } = useI18n();
const toast = useToast();

const { data: presets, refresh } = await useFetch<Preset[]>(
  '/api/admin/obfuscator-presets',
  // deep: true is required so editing a preset's fields in place (e.g. the
  // protocol select) triggers the conditional rendering below immediately,
  // without needing a save+refresh round trip. Nuxt's compatibilityVersion 4
  // defaults useFetch to a shallow ref otherwise.
  { method: 'get', deep: true }
);

const createOpen = ref(false);
const creating = ref(false);
const newPreset = ref<{ name: string; mode: Mode }>({
  name: '',
  mode: 'WIREGUARD',
});

const canCreate = computed(() => newPreset.value.name.trim().length > 0);

function dummyDisabled(p: Preset): boolean {
  return p.masking === 'MEDIA' || p.obfuscateBytes > 0;
}

function mediaSsrcDisabled(p: Preset): boolean {
  return p.masking !== 'MEDIA';
}

// Reliable MEDIA-frame detection in socks5 mode benefits from a fixed
// media-ssrc (unlike WireGuard mode's per-connection UDP autodetect), so fill
// one in immediately when switching to MEDIA rather than leaving it unset.
function onMaskingChange(p: Preset) {
  if (p.mode === 'SOCKS5' && p.masking === 'MEDIA' && !p.mediaSsrc) {
    p.mediaSsrc = Math.floor(Math.random() * 0xfffffffe) + 1;
  }
}

async function create() {
  if (!canCreate.value) return;
  creating.value = true;
  try {
    await $fetch('/api/admin/obfuscator-presets', {
      method: 'post',
      body: {
        name: newPreset.value.name.trim(),
        mode: newPreset.value.mode,
      },
    });
    await refresh();
    createOpen.value = false;
    newPreset.value = { name: '', mode: 'WIREGUARD' };
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
        mode: p.mode,
        extPort: p.extPort,
        sourceIf: p.sourceIf,
        target: p.target ?? '',
        key: p.key,
        masking: p.masking,
        obfuscateBytes: p.obfuscateBytes,
        dummy: p.dummy,
        verbose: p.verbose,
        clientWgLocalPort: p.clientWgLocalPort,
        mediaSsrc: p.mediaSsrc,
        clientLocalPort: p.clientLocalPort,
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
