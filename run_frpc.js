#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { loadLocalEnvFiles } from './src/env-local.js';
import { serverDirectory } from './src/server-directory.js';

loadLocalEnvFiles(serverDirectory);
process.chdir(serverDirectory);

const bundledFrpc = path.join(serverDirectory, '.tools/frp_0.69.0_darwin_arm64/frpc');
const frpcBin = process.env.FRP_CLIENT_BIN || (fs.existsSync(bundledFrpc) ? bundledFrpc : 'frpc');
const configPath = process.env.FRP_CONFIG_PATH || 'frpc.headless.toml';
const passthroughArgs = process.argv.slice(2);
const args = passthroughArgs.length > 0
    ? [...passthroughArgs, '-c', configPath]
    : ['-c', configPath];

const child = spawn(frpcBin, args, {
    env: process.env,
    stdio: 'inherit',
});

child.on('error', error => {
    console.error(`Failed to start frpc from "${frpcBin}". Set FRP_CLIENT_BIN in .env.local or install frpc on PATH.`);
    console.error(error.message);
    process.exit(1);
});

child.on('exit', (code, signal) => {
    if (signal) {
        console.error(`frpc exited after signal ${signal}`);
        process.exit(1);
    }

    process.exit(code ?? 1);
});
