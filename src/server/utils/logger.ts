import { readRuntimeEnv } from './env';

const enabledNamespaces = new Set(
  (readRuntimeEnv('DEBUG') ?? '')
    .split(',')
    .map((ns) => ns.trim())
    .filter(Boolean)
);

type Logger = (...args: unknown[]) => void;

const silent: Logger = () => {};

export function createLogger(namespace: string): Logger {
  if (!enabledNamespaces.has('*') && !enabledNamespaces.has(namespace)) {
    return silent;
  }
  return (...args) => console.debug(`[${namespace}]`, ...args);
}
