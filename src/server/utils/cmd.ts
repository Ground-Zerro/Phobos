import childProcess from 'child_process';
import { createLogger } from './logger';

const CMD_DEBUG = createLogger('CMD');

export function exec(
  cmd: string,
  { log }: { log: boolean | string } = { log: true }
) {
  if (typeof log === 'string') {
    CMD_DEBUG(`$ ${log}`);
  } else if (log === true) {
    CMD_DEBUG(`$ ${cmd}`);
  }

  if (process.platform !== 'linux') {
    return Promise.resolve('');
  }

  return new Promise<string>((resolve, reject) => {
    childProcess.exec(
      cmd,
      {
        shell: 'bash',
      },
      (err, stdout) => {
        if (err) return reject(err);
        return resolve(String(stdout).trim());
      }
    );
  });
}

type ExecFileOptions = {
  input?: string;
  log?: boolean;
};

export function execFile(
  file: string,
  args: readonly string[],
  { input, log = true }: ExecFileOptions = {}
) {
  if (log) {
    CMD_DEBUG(`$ ${file} ${args.join(' ')}`);
  }

  if (process.platform !== 'linux') {
    return Promise.resolve('');
  }

  return new Promise<string>((resolve, reject) => {
    const child = childProcess.execFile(file, args, (err, stdout) => {
      if (err) return reject(err);
      return resolve(stdout.trim());
    });
    child.stdin?.end(input);
  });
}
