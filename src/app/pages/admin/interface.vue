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
        <FormHeading>{{ $t('admin.interface.egress') }}</FormHeading>
        <FormSwitchField
          id="egressWarp"
          v-model="warpEgress"
          :label="$t('admin.interface.egressWarp')"
          :description="$t('admin.interface.egressWarpDesc')"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('admin.interface.subnet') }}</FormHeading>
        <FormTextField
          id="ipv4Cidr"
          :model-value="data.ipv4Cidr"
          :on-update:model-value="() => {}"
          :disabled="true"
          :label="$t('admin.interface.ipv4Cidr')"
          :description="$t('admin.interface.ipv4CidrDesc')"
        />
        <FormTextField
          id="ipv6Cidr"
          :model-value="data.ipv6Cidr"
          :on-update:model-value="() => {}"
          :disabled="true"
          :label="$t('admin.interface.ipv6Cidr')"
          :description="$t('admin.interface.ipv6CidrDesc')"
        />
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
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('admin.interface.publicAddress') }}</FormHeading>
        <FormTextField
          id="serverPublicIpV4"
          v-model="data.serverPublicIpV4"
          :disabled="!!data.serverPublicDomain"
          :label="$t('admin.interface.publicIpV4')"
          :description="$t('admin.interface.publicIpV4Desc')"
        />
        <FormNullTextField
          id="serverPublicIpV6"
          v-model="data.serverPublicIpV6"
          :disabled="!!data.serverPublicDomain"
          :label="$t('admin.interface.publicIpV6')"
          :description="$t('admin.interface.publicIpV6Desc')"
        />
        <FormNullTextField
          id="serverPublicDomain"
          v-model="data.serverPublicDomain"
          :label="$t('admin.interface.publicDomain')"
          :description="$t('admin.interface.publicDomainDesc')"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('form.actions') }}</FormHeading>
        <FormPrimaryActionField type="submit" :label="$t('form.save')" />
        <FormSecondaryActionField :label="$t('form.revert')" @click="revert" />
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

const { data, revert } = useEditable(
  await useFetch(`/api/admin/interface`, { method: 'get' })
);

const warpEgress = computed({
  get: () => data.value?.egressMode === 'warp',
  set: (value) => {
    if (data.value) {
      data.value.egressMode = value ? 'warp' : 'wan';
    }
  },
});

const _submit = useSubmit(
  `/api/admin/interface`,
  {
    method: 'post',
  },
  {
    revert: async (success) => {
      await revert();
      if (success) {
        await globalStore.refreshInformation();
      }
    },
  }
);

function submit() {
  return _submit(data.value);
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
</script>
