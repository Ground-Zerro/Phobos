<template>
  <main class="flex flex-col gap-4">
    <p class="whitespace-pre-line text-sm text-gray-600 dark:text-neutral-300">
      {{ $t('admin.obfuscatorPresets.desc') }}
    </p>

    <div class="flex justify-end">
      <BaseDialog v-model:open="createOpen">
        <template #trigger>
          <BaseButton variant="primary" as="span">{{
            $t('admin.obfuscatorPresets.add')
          }}</BaseButton>
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
              <BaseSelect v-model="newPreset.mode" :options="modeOptions" />
            </div>
          </div>
        </template>
        <template #actions>
          <DialogClose as-child>
            <BaseButton>{{ $t('dialog.cancel') }}</BaseButton>
          </DialogClose>
          <BaseButton
            variant="primary"
            :disabled="!canCreate || creating"
            @click="create"
          >
            {{ $t('dialog.create') }}
          </BaseButton>
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
            <BaseSelect v-model="p.mode" :options="modeOptions" />
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
              <BaseButton @click="presetAction(p.id, 'regenerate-port')">
                {{ $t('admin.obfuscatorPresets.regeneratePort') }}
              </BaseButton>
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
              placeholder="AUTO"
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
              <BaseButton @click="presetAction(p.id, 'regenerate-key')">
                {{ $t('admin.obfuscatorPresets.regenerateKey') }}
              </BaseButton>
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
            <BaseSelect
              v-model="p.masking"
              :options="maskingOptions[p.mode]"
              @change="onMaskingChange(p)"
            />
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
            <BaseSelect v-model="p.verbose" :options="verbosityOptions" />
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
          <BaseButton variant="primary" @click="save(p)">
            {{ $t('form.save') }}
          </BaseButton>
          <BaseButton
            v-if="!p.isDefault"
            @click="presetAction(p.id, 'set-default')"
          >
            {{ $t('admin.obfuscatorPresets.setAsDefault') }}
          </BaseButton>
          <BaseButton
            v-if="!p.isDefault"
            class="text-red-700 dark:text-red-400"
            @click="remove(p.id)"
          >
            {{ $t('dialog.delete') }}
          </BaseButton>
        </div>
      </div>
    </div>

    <div v-else class="text-sm text-gray-500">{{ $t('general.loading') }}</div>
  </main>
</template>

<script setup lang="ts">
import {
  OBFUSCATION_MASKINGS,
  OBFUSCATOR_VERBOSITY,
  effectiveObfuscateBytes,
  isMaskingAllowed,
  type ObfuscationMode,
} from '~~/shared/utils/obfuscation';

const { t } = useI18n();
const toast = useToast();

const { data: presets, refresh } = await useFetch(
  '/api/admin/obfuscator-presets',
  { method: 'get', deep: true }
);

type Preset = NonNullable<typeof presets.value>[number];

const modeOptions = [
  { value: 'WIREGUARD', label: 'WireGuard' },
  { value: 'SOCKS5', label: 'SOCKS5' },
] as const satisfies ReadonlyArray<{ value: ObfuscationMode; label: string }>;

function textOptions<T extends string>(values: readonly T[]) {
  return values.map((value) => ({ value, label: value }));
}

function maskingsFor(mode: ObfuscationMode) {
  return textOptions(
    OBFUSCATION_MASKINGS.filter((masking) => isMaskingAllowed(mode, masking))
  );
}

const maskingOptions: Record<
  ObfuscationMode,
  ReturnType<typeof maskingsFor>
> = {
  WIREGUARD: maskingsFor('WIREGUARD'),
  SOCKS5: maskingsFor('SOCKS5'),
};

const verbosityOptions = textOptions(OBFUSCATOR_VERBOSITY);

const createOpen = ref(false);
const creating = ref(false);
const newPreset = ref<{ name: string; mode: ObfuscationMode }>({
  name: '',
  mode: 'WIREGUARD',
});

const canCreate = computed(() => newPreset.value.name.trim().length > 0);

function dummyDisabled(p: Preset): boolean {
  return effectiveObfuscateBytes(p) > 0;
}

function mediaSsrcDisabled(p: Preset): boolean {
  return p.masking !== 'MEDIA';
}

function onMaskingChange(p: Preset) {
  if (p.mode === 'SOCKS5' && p.masking === 'MEDIA' && !p.mediaSsrc) {
    p.mediaSsrc = Math.floor(Math.random() * 0xfffffffe) + 1;
  }
}

async function run(request: () => Promise<unknown>) {
  try {
    await request();
    await refresh();
    toast.showToast({ type: 'success', message: t('toast.saved') });
    return true;
  } catch (e) {
    toast.showToast({
      type: 'error',
      message: toErrorMessage(e, t('toast.unknown')),
    });
    return false;
  }
}

async function create() {
  if (!canCreate.value) return;
  creating.value = true;
  const created = await run(() =>
    $fetch('/api/admin/obfuscator-presets', {
      method: 'post',
      body: {
        name: newPreset.value.name.trim(),
        mode: newPreset.value.mode,
      },
    })
  );
  creating.value = false;
  if (created) {
    createOpen.value = false;
    newPreset.value = { name: '', mode: 'WIREGUARD' };
  }
}

function save(p: Preset) {
  return run(() =>
    $fetch(`/api/admin/obfuscator-presets/${p.id}`, {
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
    })
  );
}

function remove(id: number) {
  if (!confirm(t('admin.obfuscatorPresets.deleteConfirm'))) return;
  return run(() =>
    $fetch(`/api/admin/obfuscator-presets/${id}`, { method: 'delete' })
  );
}

function presetAction(
  id: number,
  action: 'set-default' | 'regenerate-key' | 'regenerate-port'
) {
  return run(() =>
    $fetch(`/api/admin/obfuscator-presets/${id}/${action}`, { method: 'post' })
  );
}
</script>
