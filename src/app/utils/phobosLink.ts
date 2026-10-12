const WIREGUARD_REQUIRED_FIELDS: Record<string, readonly string[]> = {
  Interface: ['PrivateKey', 'Address', 'MTU', 'DNS'],
  Peer: [
    'PublicKey',
    'PresharedKey',
    'AllowedIPs',
    'PersistentKeepalive',
    'Endpoint',
  ],
  instance: [
    'source-if',
    'source-lport',
    'target',
    'key',
    'masking',
    'verbose',
    'idle-timeout',
    'max-dummy',
  ],
};

const SOCKS5_REQUIRED_FIELDS: Record<string, readonly string[]> = {
  instance: [
    'mode',
    'role',
    'source-if',
    'source-lport',
    'target',
    'key',
    'masking',
    'verbose',
  ],
  socks5: ['login', 'password'],
};

const SOCKS5_MODE_RE = /^\s*mode\s*=\s*socks5\s*$/im;

function padConfWithNone(confText: string): string {
  const requiredFields = SOCKS5_MODE_RE.test(confText)
    ? SOCKS5_REQUIRED_FIELDS
    : WIREGUARD_REQUIRED_FIELDS;
  const sectionRe = /^\[([^\]]+)\]\s*$/;
  const lines = confText.split('\n');
  const out: string[] = [];
  let currentSection: string | null = null;
  let currentBuffer: string[] = [];

  const flush = () => {
    if (currentSection === null) {
      out.push(...currentBuffer);
      currentBuffer = [];
      return;
    }
    const required = requiredFields[currentSection];
    if (required) {
      const present = new Set(
        currentBuffer
          .map((l) => l.match(/^\s*([A-Za-z][A-Za-z0-9_-]*)\s*=/)?.[1])
          .filter((v): v is string => !!v)
      );
      for (const key of required) {
        if (!present.has(key)) currentBuffer.push(`${key} = none`);
      }
    }
    out.push(`[${currentSection}]`, ...currentBuffer);
    currentBuffer = [];
  };

  for (const rawLine of lines) {
    const line = rawLine.replace(/\r$/, '');
    const sectionMatch = line.match(sectionRe);
    if (sectionMatch) {
      flush();
      currentSection = sectionMatch[1] ?? null;
      continue;
    }
    currentBuffer.push(line);
  }
  flush();

  return out.join('\n');
}

export function buildPhobosLink(
  confText: string,
  name: string | null | undefined
): string {
  const padded = padConfWithNone(confText);
  const utf8Safe = unescape(encodeURIComponent(padded));
  const b64url = btoa(utf8Safe)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  const trimmed = name?.trim();
  const fragment =
    trimmed && trimmed.length > 0 ? encodeURIComponent(trimmed) : 'none';

  return `phobos://${b64url}#${fragment}`;
}
