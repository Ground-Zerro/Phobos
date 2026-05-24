const REQUIRED_FIELDS: Record<string, readonly string[]> = {
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

/**
 * Pad a .conf text with `key = none` lines for fields that are required by the
 * phobos:// link spec (docs/phobos-link-format.md §2.3) but absent in the
 * original config. Operates only on the section bodies we know about and does
 * not reorder existing lines.
 */
export function padConfWithNone(confText: string): string {
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
    const required = REQUIRED_FIELDS[currentSection];
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
  const fragment = trimmed && trimmed.length > 0
    ? encodeURIComponent(trimmed)
    : 'none';

  return `phobos://${b64url}#${fragment}`;
}
