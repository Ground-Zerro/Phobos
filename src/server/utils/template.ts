import type { InterfaceType } from '#db/repositories/interface/types';

export type IniEntries = ReadonlyArray<
  readonly [string, string | number | null | undefined]
>;

export function renderIni(
  sections: ReadonlyArray<readonly [string, IniEntries]>
): string {
  return (
    sections
      .map(([name, entries]) =>
        [
          `[${name}]`,
          ...entries
            .filter(([, value]) => value !== null && value !== undefined)
            .map(([key, value]) => `${key} = ${value}`),
        ].join('\n')
      )
      .join('\n\n') + '\n'
  );
}

export function joinShell(parts: readonly string[]): string {
  return parts
    .map((p) => p.trim())
    .filter(Boolean)
    .map((p) => (p.endsWith(';') ? p : `${p};`))
    .join(' ');
}

function fillTemplate(templ: string, values: Record<string, string>) {
  return templ.replace(/\{\{(\w+)\}\}/g, (match, key) => values[key] ?? match);
}

export function removeNewlines(templ: string) {
  return templ.replace(/\r\n|\r|\n/g, ' ');
}

export function iptablesTemplate(templ: string, wgInterface: InterfaceType) {
  return fillTemplate(removeNewlines(templ), {
    ipv4Cidr: wgInterface.ipv4Cidr,
    ipv6Cidr: wgInterface.ipv6Cidr,
    device: wgInterface.device,
    port: wgInterface.port.toString(),
    uiPort: WG_ENV.PORT,
  });
}
