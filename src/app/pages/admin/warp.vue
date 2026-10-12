<template>
  <main v-if="data">
    <FormElement v-if="!data.registered" @submit.prevent="register">
      <FormGroup>
        <FormHeading>{{ $t('admin.warp.title') }}</FormHeading>
        <p class="col-span-2 text-sm text-gray-500 dark:text-neutral-400">
          {{ $t('admin.warp.intro') }}
        </p>
        <FormPrimaryActionField
          type="submit"
          :label="$t('admin.warp.register')"
        />
      </FormGroup>
    </FormElement>

    <FormElement v-else @submit.prevent="() => {}">
      <FormGroup>
        <FormHeading>{{ $t('admin.warp.status') }}</FormHeading>
        <div class="flex items-center">
          <FormLabel for="connection">
            {{ $t('admin.warp.connection') }}
          </FormLabel>
        </div>
        <span id="connection" class="flex items-center gap-2">
          <template v-if="!egressActive">
            <span
              class="inline-block h-2.5 w-2.5 shrink-0 rounded-full bg-amber-400"
            />
            {{ $t('admin.warp.notActiveEgress') }}
            <BaseTooltip :text="$t('admin.warp.notActiveEgressTip')">
              <IconsInfo class="size-4" />
            </BaseTooltip>
          </template>
          <template v-else>
            <span
              class="inline-block h-2.5 w-2.5 shrink-0 rounded-full"
              :class="
                data.online ? 'animate-pulse bg-green-500' : 'bg-gray-400'
              "
            />
            {{
              data.online ? $t('admin.warp.online') : $t('admin.warp.offline')
            }}
          </template>
        </span>
        <FormSecondaryActionField
          :label="
            checking ? $t('admin.warp.checking') : $t('admin.warp.checkNow')
          "
          :disabled="!egressActive || checking"
          @click="checkNow"
        />
        <FormInfoField
          id="deviceId"
          :label="$t('admin.warp.deviceId')"
          :data="data.deviceId"
        />
        <FormInfoField
          id="addressV4"
          :label="$t('admin.warp.addressV4')"
          :data="data.addressV4"
        />
        <FormInfoField
          id="addressV6"
          :label="$t('admin.warp.addressV6')"
          :data="data.addressV6"
        />
        <FormInfoField
          id="endpoint"
          :label="$t('admin.warp.endpoint')"
          :data="data.endpoint"
        />
      </FormGroup>

      <FormGroup>
        <FormHeading>{{ $t('admin.warp.license') }}</FormHeading>
        <FormTextField
          id="license"
          v-model="license"
          :label="$t('admin.warp.licenseKey')"
          :description="$t('admin.warp.licenseKeyDesc')"
          :placeholder="
            data.hasLicense
              ? $t('admin.warp.licenseSet')
              : $t('admin.warp.licenseUnset')
          "
        />
        <FormSecondaryActionField
          :label="$t('admin.warp.applyLicense')"
          @click="applyLicense"
        />
      </FormGroup>

      <FormGroup>
        <FormHeading>{{ $t('admin.warp.autoRotate') }}</FormHeading>
        <FormNumberField
          id="interval"
          v-model="interval"
          :label="$t('admin.warp.intervalDays')"
          :description="$t('admin.warp.intervalDaysDesc')"
        />
        <FormSecondaryActionField
          :label="$t('form.save')"
          @click="saveInterval"
        />
      </FormGroup>

      <FormGroup>
        <FormHeading>{{ $t('form.actions') }}</FormHeading>
        <FormSecondaryActionField
          :label="$t('admin.warp.changeIp')"
          @click="changeIp"
        />
        <FormSecondaryActionField
          :label="$t('admin.warp.importConfig')"
          @click="importOpen = true"
        />
        <FormSecondaryActionField
          :label="$t('admin.warp.delete')"
          @click="remove"
        />
      </FormGroup>
    </FormElement>

    <WarpImportDialog v-model:open="importOpen" @success="resetForm" />
  </main>
</template>

<script setup lang="ts">
const { t } = useI18n();

const { data, revert } = useEditable(
  await useFetch(`/api/admin/warp`, { method: 'get' })
);

const toast = useToast();

const license = ref('');
const interval = ref(data.value?.updateIntervalDays ?? 0);
const importOpen = ref(false);
const checking = ref(false);

const egressActive = computed(() => data.value?.egressMode === 'warp');

async function resetForm() {
  await revert();
  license.value = '';
  interval.value = data.value?.updateIntervalDays ?? 0;
}

async function checkNow() {
  if (checking.value || !egressActive.value) {
    return;
  }
  checking.value = true;
  try {
    const res = await $fetch('/api/admin/warp/check', { method: 'post' });
    toast.showToast(
      res.online
        ? { type: 'success', message: t('admin.warp.checkOnline') }
        : { type: 'error', message: t('admin.warp.checkOffline') }
    );
    await revert();
  } catch (e) {
    toast.showToast({
      type: 'error',
      message: toErrorMessage(e, t('admin.warp.checkOffline')),
    });
  } finally {
    checking.value = false;
  }
}

const statusPoll = ref<NodeJS.Timeout | null>(null);

onMounted(() => {
  statusPoll.value = setInterval(() => {
    if (data.value?.registered) {
      revert().catch(console.error);
    }
  }, 5000);
});

onUnmounted(() => {
  if (statusPoll.value !== null) {
    clearInterval(statusPoll.value);
    statusPoll.value = null;
  }
});

const _register = useSubmit(
  `/api/admin/warp/register`,
  { method: 'post' },
  { revert: resetForm, successMsg: t('admin.warp.registerSuccess') }
);

const _applyLicense = useSubmit(
  `/api/admin/warp/license`,
  { method: 'post' },
  { revert: resetForm, successMsg: t('admin.warp.licenseSuccess') }
);

const _saveInterval = useSubmit(
  `/api/admin/warp/interval`,
  { method: 'post' },
  { revert: resetForm }
);

const _changeIp = useSubmit(
  `/api/admin/warp/change-ip`,
  { method: 'post' },
  { revert: resetForm, successMsg: t('admin.warp.changeIpSuccess') }
);

const _remove = useSubmit(
  `/api/admin/warp`,
  { method: 'delete' },
  { revert: resetForm, successMsg: t('admin.warp.deleteSuccess') }
);

function register() {
  return _register(undefined);
}

function applyLicense() {
  return _applyLicense({ license: license.value });
}

function saveInterval() {
  return _saveInterval({ updateIntervalDays: interval.value });
}

function changeIp() {
  return _changeIp(undefined);
}

function remove() {
  return _remove(undefined);
}
</script>
