export function readRuntimeEnv(name: string): string | undefined {
  return process.env[name];
}
