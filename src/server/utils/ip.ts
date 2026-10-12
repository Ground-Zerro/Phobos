import { parseIp, stringifyIp } from 'ip-bigint';
import type { parseCidr } from 'cidr-tools';

type ParsedCidr = ReturnType<typeof parseCidr>;

export function nextIP(
  version: 4 | 6,
  cidr: ParsedCidr,
  taken: ReadonlySet<string>
): string {
  for (let i = cidr.start + 2n; i <= cidr.end - 1n; i++) {
    const candidate = stringifyIp({ number: i, version });
    if (!taken.has(candidate)) {
      return candidate;
    }
  }
  throw new Error('Maximum number of clients reached', {
    cause: `IPv${version} Address Pool exhausted`,
  });
}

export function isAssignableIP(cidr: ParsedCidr, address: string): boolean {
  const { number, version } = parseIp(address);
  return (
    version === cidr.version &&
    number >= cidr.start + 2n &&
    number <= cidr.end - 1n
  );
}
