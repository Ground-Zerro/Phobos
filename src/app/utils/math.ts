const DECIMAL_UNITS = [
  'B',
  'KB',
  'MB',
  'GB',
  'TB',
  'PB',
  'EB',
  'ZB',
  'YB',
  'BB',
] as const;
const BINARY_UNITS = [
  'B',
  'KiB',
  'MiB',
  'GiB',
  'TiB',
  'PiB',
  'EiB',
  'ZiB',
  'YiB',
  'BiB',
] as const;

export function bytes(
  bytes: number,
  decimals = 2,
  kib = false,
  maxunit?: string
) {
  if (bytes === 0) return '0 B';
  if (Number.isNaN(bytes)) return 'NaN';
  const k = kib ? 1024 : 1000;
  const dm =
    decimals != null && !Number.isNaN(decimals) && decimals >= 0 ? decimals : 2;
  const sizes: readonly string[] = kib ? BINARY_UNITS : DECIMAL_UNITS;
  let i = Math.floor(Math.log(bytes) / Math.log(k));
  if (maxunit !== undefined) {
    const index = sizes.indexOf(maxunit);
    if (index !== -1) i = index;
  }
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`;
}

export function sortByProperty<T>(
  array: T[],
  property: keyof T,
  ascending: boolean = true
): T[] {
  const direction = ascending ? 1 : -1;
  return array.sort((a, b) => {
    const left = a[property];
    const right = b[property];
    return (
      direction *
      (typeof left === 'string'
        ? left.localeCompare(right as string)
        : (left as number) - (right as number))
    );
  });
}
