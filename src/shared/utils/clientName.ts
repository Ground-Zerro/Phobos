export const CLIENT_NAME_MAX_LENGTH = 32;

export const CLIENT_NAME_PATTERN = /^[A-Za-z0-9.@-]+$/;

type ClientNameIssue = 'empty' | 'tooLong' | 'invalidChars';

export function validateClientName(name: string): ClientNameIssue | null {
  const value = name.trim();
  if (value.length === 0) {
    return 'empty';
  }
  if (value.length > CLIENT_NAME_MAX_LENGTH) {
    return 'tooLong';
  }
  if (!CLIENT_NAME_PATTERN.test(value)) {
    return 'invalidChars';
  }
  return null;
}

export function normalizeClientName(name: string): string {
  return name.trim().toLowerCase();
}
