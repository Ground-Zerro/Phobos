<template>
  <main v-if="data">
    <FormElement @submit.prevent="submit">
      <FormGroup>
        <FormNumberField
          id="session"
          v-model="data.sessionTimeout"
          :label="$t('admin.general.sessionTimeout')"
          :description="$t('admin.general.sessionTimeoutDesc')"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('admin.general.metrics') }}</FormHeading>
        <FormPasswordField
          id="password"
          v-model="metricsPassword"
          autocomplete="new-password"
          :label="$t('admin.general.metricsPassword')"
          :description="$t('admin.general.metricsPasswordDesc')"
          :placeholder="
            data.metricsPasswordSet
              ? $t('admin.general.metricsPasswordSet')
              : $t('admin.general.metricsPasswordUnset')
          "
        />
        <FormSwitchField
          id="prometheus"
          v-model="data.metricsPrometheus"
          :label="$t('admin.general.prometheus')"
          :description="$t('admin.general.prometheusDesc')"
        />
        <FormSwitchField
          id="json"
          v-model="data.metricsJson"
          :label="$t('admin.general.json')"
          :description="$t('admin.general.jsonDesc')"
        />
      </FormGroup>
      <FormGroup>
        <FormHeading>{{ $t('form.actions') }}</FormHeading>
        <FormPrimaryActionField type="submit" :label="$t('form.save')" />
        <FormSecondaryActionField :label="$t('form.revert')" @click="revert" />
      </FormGroup>
    </FormElement>
  </main>
</template>

<script setup lang="ts">
const { data: _data, refresh } = await useFetch(`/api/admin/general`, {
  method: 'get',
});
const data = toRef(_data.value);

const metricsPassword = ref('');

const _submit = useSubmit(
  `/api/admin/general`,
  {
    method: 'post',
  },
  { revert }
);

function submit() {
  if (!data.value) return;
  const body: {
    sessionTimeout: number;
    metricsPrometheus: boolean;
    metricsJson: boolean;
    metricsPassword?: string;
  } = {
    sessionTimeout: data.value.sessionTimeout,
    metricsPrometheus: data.value.metricsPrometheus,
    metricsJson: data.value.metricsJson,
  };
  if (metricsPassword.value) {
    body.metricsPassword = metricsPassword.value;
  }
  return _submit(body);
}

async function revert() {
  metricsPassword.value = '';
  await refresh();
  data.value = toRef(_data.value).value;
}
</script>
