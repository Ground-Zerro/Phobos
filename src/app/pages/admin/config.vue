<template>
  <main v-if="data">
    <FormElement @submit.prevent="submit">
      <FormGroup>
        <FormHeading>{{ $t('admin.config.connection') }}</FormHeading>
        <div class="flex items-center">
          <FormLabel for="host">{{ $t('general.host') }}</FormLabel>
          <BaseTooltip :text="$t('admin.config.hostDesc')">
            <IconsInfo class="size-4" />
          </BaseTooltip>
        </div>
        <BaseInput
          id="host"
          v-model.trim="data.host"
          name="host"
          type="text"
          class="w-full"
          placeholder="vpn.example.com"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading :description="$t('admin.config.allowedIpsDesc')">
          {{ $t('general.allowedIps') }}
        </FormHeading>
        <FormArrayField
          v-model="data.defaultAllowedIps"
          name="defaultAllowedIps"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading :description="$t('admin.config.dnsDesc')">
          {{ $t('general.dns') }}
        </FormHeading>
        <FormArrayField v-model="data.defaultDns" name="defaultDns" />
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('form.sectionAdvanced') }}</FormHeading>
        <FormNumberField
          id="defaultMtu"
          v-model="data.defaultMtu"
          :label="$t('general.mtu')"
          :description="$t('admin.config.mtuDesc')"
        />
        <FormNumberField
          id="defaultPersistentKeepalive"
          v-model="data.defaultPersistentKeepalive"
          :label="$t('general.persistentKeepalive')"
          :description="$t('admin.config.persistentKeepaliveDesc')"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('form.actions') }}</FormHeading>
        <FormPrimaryActionField type="submit" :label="$t('form.save')" />
        <FormSecondaryActionField :label="$t('form.revert')" @click="revert" />
      </FormGroup>
    </FormElement>

    <AdminTlsSection />
  </main>
</template>

<script lang="ts" setup>
const globalStore = useGlobalStore();

const { data: _data, refresh } = await useFetch(`/api/admin/userconfig`, {
  method: 'get',
});

const data = toRef(_data.value);

const _submit = useSubmit(
  `/api/admin/userconfig`,
  {
    method: 'post',
  },
  { revert }
);

function submit() {
  return _submit(data.value);
}

async function revert() {
  await refresh();
  data.value = toRef(_data.value).value;
}
</script>
