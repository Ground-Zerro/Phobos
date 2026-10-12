#!/usr/bin/env node

import { defineCommand, runMain, type CommandMeta } from 'citty';

import packageJson from '../package.json';
import dbAdminReset from './admin/reset';
import clientsList from './clients/list';
import clientsQr from './clients/qr';

const commands = [dbAdminReset, clientsList, clientsQr];

runMain(
  defineCommand({
    meta: {
      name: 'phoboswg',
      version: packageJson.version,
      description: 'Command Line Interface',
    },
    subCommands: Object.fromEntries(
      commands.map((cmd) => [(cmd.meta as CommandMeta).name!, cmd])
    ),
  })
);
