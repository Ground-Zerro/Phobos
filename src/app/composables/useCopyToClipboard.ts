type TextSource = string | (() => string | Promise<string>);

async function resolveText(source: TextSource): Promise<string> {
  const value = typeof source === 'function' ? await source() : source;
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('Nothing to copy');
  }
  return value;
}

function legacyCopy(text: string): boolean {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.left = '0';
  ta.style.top = '0';
  ta.style.width = '1px';
  ta.style.height = '1px';
  ta.style.padding = '0';
  ta.style.border = 'none';
  ta.style.outline = 'none';
  ta.style.boxShadow = 'none';
  ta.style.background = 'transparent';
  ta.style.clip = 'rect(0,0,0,0)';

  const root = document.fullscreenElement ?? document.body;
  root.appendChild(ta);

  let ok = false;
  try {
    ta.focus({ preventScroll: true });
    ta.setSelectionRange(0, ta.value.length);
    ok = document.execCommand('copy');
  } finally {
    root.removeChild(ta);
  }
  return ok;
}

export function useCopyToClipboard() {
  return async (source: TextSource): Promise<void> => {
    const text = await resolveText(source);
    const secure =
      typeof window !== 'undefined' &&
      window.isSecureContext &&
      !!navigator.clipboard?.writeText;

    if (secure) {
      try {
        await navigator.clipboard.writeText(text);
        return;
      } catch {
        // fall through to legacy copy
      }
    }

    if (!legacyCopy(text)) {
      throw new Error('Clipboard copy failed');
    }
  };
}
