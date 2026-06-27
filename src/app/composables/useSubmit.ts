import type { NitroFetchRequest, NitroFetchOptions } from 'nitropack/types';
import { FetchError } from 'ofetch';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type RevertFn<T = any> = (
  success: boolean,
  data: T | undefined
) => Promise<void>;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type SubmitOpts<T = any> = {
  revert: RevertFn<T>;
  successMsg?: string;
  noSuccessToast?: boolean;
};

export function useSubmit<
  R extends NitroFetchRequest,
  O extends NitroFetchOptions<R> & { body?: never },
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  T = any,
>(url: R, options: O, opts: SubmitOpts<T>) {
  const toast = useToast();

  return async (data: unknown) => {
    try {
      const res = await $fetch(url, {
        ...options,
        body: data,
      });

      if (!opts.noSuccessToast) {
        toast.showToast({
          type: 'success',
          message: opts.successMsg,
        });
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await opts.revert(true, res as any);
    } catch (e) {
      if (e instanceof FetchError) {
        toast.showToast({
          type: 'error',
          message: e.data.message,
        });
      } else if (e instanceof Error) {
        toast.showToast({
          type: 'error',
          message: e.message,
        });
      } else {
        console.error(e);
      }
      await opts.revert(false, undefined);
    }
  };
}
