import { effectiveObfuscateBytes } from '../../shared/utils/obfuscation';
import { renderIni, type IniEntries } from './template';
import { wg } from './wgHelper';

import type { ClientType } from '#db/repositories/client/types';
import type { InterfaceType } from '#db/repositories/interface/types';
import type { ObfuscatorPresetType } from '#db/repositories/obfuscatorPreset/types';
import type { UserConfigType } from '#db/repositories/userConfig/types';

export type Socks5Credentials = { login: string; password: string };

export type ClientFullConfigInput = {
  iface: InterfaceType;
  userConfig: UserConfigType;
  client: ClientType;
  preset: ObfuscatorPresetType;
  enableIpv6: boolean;
  socks5Credentials: Socks5Credentials | null;
};

function instanceEntries(
  preset: ObfuscatorPresetType,
  iface: InterfaceType,
  localPort: number
): IniEntries {
  return [
    ['source-if', '127.0.0.1'],
    ['source-lport', localPort],
    [
      'target',
      `${iface.serverPublicDomain || iface.serverPublicIpV4}:${preset.extPort}`,
    ],
    ['key', preset.key],
    ['masking', preset.masking],
  ];
}

export function buildWireguardObfConf(
  preset: ObfuscatorPresetType,
  iface: InterfaceType
): string {
  return renderIni([
    [
      'instance',
      [
        ...instanceEntries(preset, iface, preset.clientWgLocalPort),
        ['obfuscate-bytes', effectiveObfuscateBytes(preset)],
        ['max-dummy', preset.dummy],
        ['verbose', preset.verbose],
      ],
    ],
  ]);
}

export function buildSocks5ObfConf(
  preset: ObfuscatorPresetType,
  iface: InterfaceType
): string {
  return renderIni([
    [
      'instance',
      [
        ['mode', 'socks5'],
        ['role', 'client'],
        ...instanceEntries(preset, iface, preset.clientLocalPort),
        ['verbose', preset.verbose],
        ['media-ssrc', preset.masking === 'MEDIA' ? preset.mediaSsrc : null],
      ],
    ],
  ]);
}

function buildSocks5CredentialsSection({
  login,
  password,
}: Socks5Credentials): string {
  return renderIni([
    [
      'socks5',
      [
        ['login', login],
        ['password', password],
      ],
    ],
  ]);
}

export function buildClientFullConfig({
  iface,
  userConfig,
  client,
  preset,
  enableIpv6,
  socks5Credentials,
}: ClientFullConfigInput): string {
  if (preset.mode === 'SOCKS5') {
    if (!socks5Credentials) {
      throw new Error(`Client ${client.id} has no SOCKS5 credentials`);
    }
    return `${buildSocks5ObfConf(preset, iface).trimEnd()}\n\n${buildSocks5CredentialsSection(socks5Credentials)}`;
  }

  const wgConfig = wg.generateClientConfig(iface, userConfig, client, {
    enableIpv6,
    clientWgLocalPort: preset.clientWgLocalPort,
  });
  return `${wgConfig.trimEnd()}\n\n${buildWireguardObfConf(preset, iface)}`;
}
