<template>
  <main v-if="data">
    <FormElement @submit.prevent="submit">
      <FormGroup>
        <FormNumberField
          id="mtu"
          v-model="data.mtu"
          :label="$t('general.mtu')"
          :description="$t('admin.interface.mtuDesc')"
        />
        <FormTextField
          id="device"
          v-model="data.device"
          :label="$t('admin.interface.device')"
          :description="$t('admin.interface.deviceDesc')"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('admin.interface.firewall') }}</FormHeading>
        <FormSwitchField
          id="firewallEnabled"
          v-model="data.firewallEnabled"
          :label="$t('admin.interface.firewallEnabled')"
          :description="$t('admin.interface.firewallEnabledDesc')"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('admin.obfuscator.heading') }}</FormHeading>

        <FormNumberField
          id="obfuscatorExtPort"
          v-model="data.obfuscatorExtPort"
          :label="$t('admin.obfuscator.extPort')"
          :description="$t('admin.obfuscator.extPortDesc')"
          :disabled="isPortPinned"
        />
        <FormSecondaryActionField
          v-if="!isPortPinned"
          :label="$t('admin.obfuscator.regeneratePort')"
          @click="regeneratePort"
        />
        <FormTextField
          id="obfuscatorKey"
          v-model="data.obfuscatorKey"
          :label="$t('admin.obfuscator.key')"
          :description="$t('admin.obfuscator.keyDesc')"
        />
        <FormSecondaryActionField
          :label="$t('admin.obfuscator.regenerateKey')"
          @click="regenerateKey"
        />
        <FormTextField
          id="obfuscatorMasking"
          v-model="data.obfuscatorMasking"
          :label="$t('admin.obfuscator.masking')"
          :description="$t('admin.obfuscator.maskingDesc')"
        />
        <FormNumberField
          id="obfuscatorIdle"
          v-model="data.obfuscatorIdle"
          :label="$t('admin.obfuscator.idle')"
          :description="$t('admin.obfuscator.idleDesc')"
        />
        <FormNumberField
          id="obfuscatorDummy"
          v-model="data.obfuscatorDummy"
          :label="$t('admin.obfuscator.dummy')"
          :description="$t('admin.obfuscator.dummyDesc')"
        />
        <FormTextField
          id="serverPublicIpV4"
          v-model="data.serverPublicIpV4"
          :label="$t('admin.obfuscator.publicIpV4')"
          :description="$t('admin.obfuscator.publicIpV4Desc')"
        />
        <FormNullTextField
          id="serverPublicIpV6"
          v-model="data.serverPublicIpV6"
          :label="$t('admin.obfuscator.publicIpV6')"
          :description="$t('admin.obfuscator.publicIpV6Desc')"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('form.actions') }}</FormHeading>
        <FormPrimaryActionField type="submit" :label="$t('form.save')" />
        <FormSecondaryActionField :label="$t('form.revert')" @click="revert" />
        <AdminCidrDialog
          trigger-class="col-span-2"
          :ipv4-cidr="data.ipv4Cidr"
          :ipv6-cidr="data.ipv6Cidr"
          @change="changeCidr"
        >
          <FormSecondaryActionField
            :label="$t('admin.interface.changeCidr')"
            class="w-full"
            tabindex="-1"
          />
        </AdminCidrDialog>
        <AdminRestartInterfaceDialog
          trigger-class="col-span-2"
          @restart="restartInterface"
        >
          <FormSecondaryActionField
            :label="$t('admin.interface.restart')"
            class="w-full"
            tabindex="-1"
          />
        </AdminRestartInterfaceDialog>
      </FormGroup>
    </FormElement>
  </main>
</template>

<script setup lang="ts">
const globalStore = useGlobalStore();

const { t } = useI18n();

const { data: _data, refresh } = await useFetch(`/api/admin/interface`, {
  method: 'get',
});

const data = toRef(_data.value);

const _submit = useSubmit(
  `/api/admin/interface`,
  {
    method: 'post',
  },
  {
    revert: async (success) => {
      await revert();
      if (success) {
        // Refresh global store information after successful save
        await globalStore.refreshInformation();
      }
    },
  }
);

function submit() {
  return _submit(data.value);
}

async function revert() {
  await refresh();
  data.value = toRef(_data.value).value;
}

const _changeCidr = useSubmit(
  `/api/admin/interface/cidr`,
  {
    method: 'post',
  },
  {
    revert,
    successMsg: t('admin.interface.cidrSuccess'),
  }
);

async function changeCidr(ipv4Cidr: string, ipv6Cidr: string) {
  await _changeCidr({ ipv4Cidr, ipv6Cidr });
}

const _restartInterface = useSubmit(
  `/api/admin/interface/restart`,
  {
    method: 'post',
  },
  {
    revert,
    successMsg: t('admin.interface.restartSuccess'),
  }
);

async function restartInterface() {
  await _restartInterface(undefined);
}

const isPortPinned = computed(
  () => globalStore.information?.obfuscatorPortPinned ?? false
);

const _regenerateKey = useSubmit<{ key: string }>(
  '/api/admin/interface/regenerateObfuscatorKey',
  { method: 'post' },
  {
    revert: async (success) => {
      if (success) await revert();
    },
    successMsg: t('admin.obfuscator.keyRegenerated'),
  }
);

async function regenerateKey() {
  await _regenerateKey(undefined);
}

const _regeneratePort = useSubmit<{ port: number }>(
  '/api/admin/interface/regenerateObfuscatorPort',
  { method: 'post' },
  {
    revert: async (success) => {
      if (success) await revert();
    },
    successMsg: t('admin.obfuscator.portRegenerated'),
  }
);

async function regeneratePort() {
  await _regeneratePort(undefined);
}
</script>
