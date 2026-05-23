import { getConfigValue } from './util.js';

/**
 * Gets headless remote app configuration from the regular SillyTavern config flow.
 * @returns {{
 * enabled: boolean,
 * publicUrl: string,
 * proxyTarget: string,
 * appPath: string,
 * apiPath: string,
 * assetPaths: string[],
 * healthPath: string,
 * }}
 */
export function getHeadlessRemoteConfig() {
    return {
        enabled: getConfigValue('headless.remoteApp.enabled', false, 'boolean'),
        publicUrl: String(getConfigValue('headless.remoteApp.publicUrl', '') ?? '').trim(),
        proxyTarget: String(getConfigValue('headless.remoteApp.proxyTarget', 'http://127.0.0.1:8000') ?? '').trim(),
        appPath: String(getConfigValue('headless.remoteApp.appPath', '/headless/') ?? '/headless/'),
        apiPath: String(getConfigValue('headless.remoteApp.apiPath', '/api/headless/v1') ?? '/api/headless/v1'),
        assetPaths: getConfigValue('headless.remoteApp.assetPaths', ['/thumbnail', '/characters', '/backgrounds']),
        healthPath: String(getConfigValue('headless.remoteApp.healthPath', '/api/headless/v1/bootstrap') ?? '/api/headless/v1/bootstrap'),
    };
}

/**
 * Logs headless remote app configuration in a concise startup-friendly format.
 * @param {ReturnType<typeof getHeadlessRemoteConfig>} config Headless remote config
 */
export function logHeadlessRemoteConfig(config) {
    if (!config.enabled) {
        console.log('Headless remote app config: disabled');
        return;
    }

    console.log('Headless remote app config: enabled');
    console.log(`  Public URL: ${config.publicUrl || '(not set)'}`);
    console.log(`  Proxy target: ${config.proxyTarget}`);
    console.log(`  App path: ${config.appPath}`);
    console.log(`  API path: ${config.apiPath}`);
    console.log(`  Health path: ${config.healthPath}`);
    console.log(`  Asset paths: ${Array.isArray(config.assetPaths) ? config.assetPaths.join(', ') : '(not set)'}`);
}
