#!/usr/bin/env node
import { CommandLineParser } from './src/command-line.js';
import { serverDirectory } from './src/server-directory.js';
import { getHeadlessRemoteConfig, logHeadlessRemoteConfig } from './src/headless-config.js';

console.log(`Node version: ${process.version}. Running in ${process.env.NODE_ENV} environment. Server directory: ${serverDirectory}`);

// Reuse SillyTavern's normal config and CLI flow.
const cliArgs = new CommandLineParser().parse(process.argv);
globalThis.DATA_ROOT = cliArgs.dataRoot;
globalThis.COMMAND_LINE_ARGS = cliArgs;
process.chdir(serverDirectory);

logHeadlessRemoteConfig(getHeadlessRemoteConfig());

try {
    await import('./src/server-main.js');
} catch (error) {
    console.error('A critical error has occurred while starting the server:', error);
}
