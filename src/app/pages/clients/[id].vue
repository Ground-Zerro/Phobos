<template>
  <main v-if="data">
    <Panel>
      <PanelHead>
        <PanelHeadTitle>
          {{ data.name }}
        </PanelHeadTitle>
      </PanelHead>
      <PanelBody>
        <FormElement @submit.prevent="submit">
          <FormGroup>
            <FormHeading>
              {{ $t('form.sectionGeneral') }}
            </FormHeading>
            <FormTextField
              id="name"
              v-model="data.name"
              :label="$t('general.name')"
            />
            <FormSwitchField
              id="enabled"
              v-model="data.enabled"
              :label="$t('client.enabled')"
            />
            <FormDateField
              id="expiresAt"
              v-model="data.expiresAt"
              :description="$t('client.expireDateDesc')"
              :label="$t('client.expireDate')"
            />
          </FormGroup>
          <FormGroup>
            <FormHeading>{{ $t('client.address') }}</FormHeading>
            <FormTextField
              id="ipv4Address"
              v-model="data.ipv4Address"
              label="IPv4"
            />
            <FormTextField
              id="ipv6Address"
              v-model="data.ipv6Address"
              label="IPv6"
            />
            <FormInfoField
              id="endpoint"
              :data="data.endpoint ?? $t('client.notConnected')"
              :label="$t('client.endpoint')"
              :description="$t('client.endpointDesc')"
            />
          </FormGroup>
          <FormGroup>
            <FormHeading :description="$t('client.presetDesc')">
              {{ $t('client.preset') }}
            </FormHeading>
            <div class="flex flex-col gap-1">
              <FormLabel for="presetId">{{ $t('client.preset') }}</FormLabel>
              <select
                id="presetId"
                v-model="data.presetId"
                class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
              >
                <option :value="null">
                  {{ $t('client.presetUseDefault') }}
                </option>
                <option v-for="p in presetList" :key="p.id" :value="p.id">
                  {{ p.name }} ({{
                    p.mode === 'SOCKS5' ? 'SOCKS5' : 'WireGuard'
                  }})
                </option>
              </select>
            </div>
            <template
              v-if="
                selectedPresetMode === 'SOCKS5' &&
                data.socks5Login &&
                data.socks5Password
              "
            >
              <FormInfoField
                id="socks5Login"
                :data="data.socks5Login"
                :label="$t('client.socks5Login')"
              />
              <FormInfoField
                id="socks5Password"
                :data="data.socks5Password"
                :label="$t('client.socks5Password')"
              />
              <p class="text-xs text-gray-500 dark:text-neutral-400">
                {{ $t('client.socks5CredentialsHint') }}
              </p>
            </template>
          </FormGroup>
          <FormGroup>
            <FormHeading :description="$t('client.allowedIpsDesc')">
              {{ $t('general.allowedIps') }}
            </FormHeading>
            <FormNullArrayField v-model="data.allowedIps" name="allowedIps" />
          </FormGroup>
          <FormGroup>
            <FormHeading :description="$t('client.serverAllowedIpsDesc')">
              {{ $t('client.serverAllowedIps') }}
            </FormHeading>
            <FormArrayField
              v-model="data.serverAllowedIps"
              name="serverAllowedIps"
            />
          </FormGroup>
          <FormGroup v-if="globalStore.information?.firewallEnabled">
            <FormHeading :description="$t('client.firewallIpsDesc')">
              {{ $t('client.firewallIps') }}
            </FormHeading>
            <FormNullArrayField v-model="data.firewallIps" name="firewallIps" />
          </FormGroup>
          <FormGroup>
            <FormHeading :description="$t('client.dnsDesc')">
              {{ $t('general.dns') }}
            </FormHeading>
            <FormNullArrayField v-model="data.dns" name="dns" />
          </FormGroup>
          <FormGroup>
            <FormHeading>{{ $t('form.sectionAdvanced') }}</FormHeading>
            <FormNumberField
              id="mtu"
              v-model="data.mtu"
              :description="$t('client.mtuDesc')"
              :label="$t('general.mtu')"
            />
            <FormNumberField
              id="persistentKeepalive"
              v-model="data.persistentKeepalive"
              :description="$t('client.persistentKeepaliveDesc')"
              :label="$t('general.persistentKeepalive')"
            />
          </FormGroup>
          <FormGroup>
            <FormHeading :description="$t('client.hooksDescription')">
              {{ $t('client.hooks') }}
            </FormHeading>
            <FormTextArea
              id="PreUp"
              v-model="data.preUp"
              :description="$t('client.hooksLeaveEmpty')"
              :label="$t('hooks.preUp')"
            />
            <FormTextArea
              id="PostUp"
              v-model="data.postUp"
              :description="$t('client.hooksLeaveEmpty')"
              :label="$t('hooks.postUp')"
            />
            <FormTextArea
              id="PreDown"
              v-model="data.preDown"
              :description="$t('client.hooksLeaveEmpty')"
              :label="$t('hooks.preDown')"
            />
            <FormTextArea
              id="PostDown"
              v-model="data.postDown"
              :description="$t('client.hooksLeaveEmpty')"
              :label="$t('hooks.postDown')"
            />
          </FormGroup>
          <FormGroup>
            <FormHeading>{{ $t('form.actions') }}</FormHeading>
            <FormPrimaryActionField type="submit" :label="$t('form.save')" />
            <FormSecondaryActionField
              :label="$t('form.revert')"
              @click="revert"
            />
            <ClientsDeleteDialog
              trigger-class="col-span-2"
              :client-name="data.name"
              @delete="deleteClient"
            >
              <FormSecondaryActionField
                :label="$t('client.delete')"
                class="w-full"
                type="button"
                tabindex="-1"
                as="span"
              />
            </ClientsDeleteDialog>
            <ClientsConfigDialog
              trigger-class="col-span-2"
              :client-id="data.id"
              :has-socks5="selectedPresetMode === 'SOCKS5'"
            >
              <FormSecondaryActionField
                :label="$t('client.viewConfig')"
                class="w-full"
                type="button"
                tabindex="-1"
                as="span"
              />
            </ClientsConfigDialog>
          </FormGroup>
        </FormElement>
      </PanelBody>
    </Panel>
  </main>
</template>

<script lang="ts" setup>
const globalStore = useGlobalStore();

const route = useRoute();
const id = route.params.id as string;

type PresetSummary = {
  id: number;
  name: string;
  isDefault: boolean;
  mode: 'WIREGUARD' | 'SOCKS5';
};

const { data: _data, refresh } = await useFetch(`/api/client/${id}`, {
  method: 'get',
});
const data = toRef(_data.value);

const { data: presets } = await useFetch<PresetSummary[]>(
  '/api/admin/obfuscator-presets',
  { method: 'get', default: () => [] }
);
const presetList = computed(() =>
  (presets.value ?? []).filter((p) => !p.isDefault)
);
const selectedPresetMode = computed(() => {
  if (data.value?.presetId == null) return 'WIREGUARD';
  return (
    (presets.value ?? []).find((p) => p.id === data.value?.presetId)?.mode ??
    'WIREGUARD'
  );
});

const _submit = useSubmit(
  `/api/client/${id}`,
  {
    method: 'post',
  },
  {
    revert: async (success) => {
      if (success) {
        await navigateTo('/');
      } else {
        await revert();
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

const _deleteClient = useSubmit(
  `/api/client/${id}`,
  {
    method: 'delete',
  },
  {
    revert: async () => {
      await navigateTo('/');
    },
  }
);

function deleteClient() {
  return _deleteClient(undefined);
}
</script>
