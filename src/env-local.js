import fs from 'node:fs';
import path from 'node:path';

const LOCAL_ENV_FILES = ['.env.local'];

/**
 * Parses a minimal dotenv-compatible file.
 * @param {string} content File contents
 * @returns {Record<string, string>}
 */
export function parseEnvFile(content) {
    const result = {};

    for (const rawLine of content.split(/\r?\n/)) {
        const line = rawLine.trim();

        if (!line || line.startsWith('#')) {
            continue;
        }

        const match = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);

        if (!match) {
            continue;
        }

        const [, key, rawValue] = match;
        result[key] = parseEnvValue(rawValue);
    }

    return result;
}

/**
 * Loads local environment overrides without replacing values already provided
 * by the parent process.
 * @param {string} root Directory to search for local env files
 * @param {string[]} files File names to load
 * @returns {string[]} Loaded file paths
 */
export function loadLocalEnvFiles(root, files = LOCAL_ENV_FILES) {
    const loadedFiles = [];

    for (const fileName of files) {
        const envPath = path.resolve(root, fileName);

        if (!fs.existsSync(envPath)) {
            continue;
        }

        const parsed = parseEnvFile(fs.readFileSync(envPath, 'utf8'));

        for (const [key, value] of Object.entries(parsed)) {
            if (!(key in process.env)) {
                process.env[key] = value;
            }
        }

        loadedFiles.push(envPath);
    }

    if (loadedFiles.length > 0) {
        const relativeFiles = loadedFiles.map(filePath => path.relative(root, filePath));
        console.log(`Loaded local env file(s): ${relativeFiles.join(', ')}`);
    }

    return loadedFiles;
}

/**
 * @param {string} rawValue Raw value from a dotenv line
 * @returns {string}
 */
function parseEnvValue(rawValue) {
    let value = rawValue.trim();

    if (value.startsWith('"') && value.endsWith('"')) {
        return value
            .slice(1, -1)
            .replace(/\\n/g, '\n')
            .replace(/\\r/g, '\r')
            .replace(/\\t/g, '\t')
            .replace(/\\"/g, '"')
            .replace(/\\\\/g, '\\');
    }

    if (value.startsWith('\'') && value.endsWith('\'')) {
        return value.slice(1, -1);
    }

    const commentIndex = value.search(/\s+#/);

    if (commentIndex !== -1) {
        value = value.slice(0, commentIndex).trimEnd();
    }

    return value;
}
