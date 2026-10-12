import type { NitroFetchOptions, NitroFetchRequest } from 'nitropack/types';

type SubmitOpts<T> = {
  revert: (success: boolean, data: T | undefined) => Promise<void> | void;
  successMsg?: string;
  noSuccessToast?: boolean;
};

export function useSubmit<T = unknown>(
  url: MaybeRefOrGetter<string>,
  options: NitroFetchOptions<NitroFetchRequest> & { body?: never },
  opts: SubmitOpts<T>
) {
  const toast = useToast();
  const { t } = useI18n();

  return async (data: unknown) => {
    try {
      const res = (await $fetch(toValue(url), {
        ...options,
        body: data as BodyInit,
      })) as T;

      if (!opts.noSuccessToast) {
        toast.showToast({ type: 'success', message: opts.successMsg });
      }

      await opts.revert(true, res);
    } catch (e) {
      toast.showToast({
        type: 'error',
        message: toErrorMessage(e, t('toast.unknown')),
      });
      await opts.revert(false, undefined);
    }
  };
}
