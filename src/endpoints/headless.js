import fs from 'node:fs';
import path from 'node:path';

import express from 'express';
import sanitize from 'sanitize-filename';
import { sync as writeFileAtomicSync } from 'write-file-atomic';

import { processCharacter, mergeCharacterUpdate } from './characters.js';
import { getChatData, getChatInfo, trySaveChat } from './chats.js';
import { readWorldInfoFile } from './worldinfo.js';
import { getHeadlessRemoteConfig } from '../headless-config.js';
import { getImages, humanizedDateTime, isPathUnderParent, tryDeleteFile, tryParse } from '../util.js';

export const router = express.Router();

const HEADLESS_API_VERSION = 'v1';
const CHAT_EXTENSION = '.jsonl';
const WORLD_EXTENSION = '.json';

/**
 * Wraps an async Express route and forwards failures to the router error handler.
 * @param {(request: import('express').Request, response: import('express').Response) => Promise<unknown>} handler Route handler
 * @returns {import('express').RequestHandler} Express route handler
 */
function asyncRoute(handler) {
    return (request, response, next) => {
        Promise.resolve(handler(request, response)).catch(next);
    };
}

/**
 * Decodes a URL path parameter.
 * @param {string} value URL parameter value
 * @returns {string} Decoded value
 */
function decodePathParam(value) {
    return decodeURIComponent(String(value ?? '').trim());
}

/**
 * Sanitizes and validates a file name from a route parameter.
 * @param {string} value File name candidate
 * @param {string} extension Expected extension, including the dot
 * @returns {string} Safe file name
 */
function getSafeFileName(value, extension) {
    const decoded = decodePathParam(value);
    const fileName = path.extname(decoded) ? decoded : `${decoded}${extension}`;
    const sanitized = sanitize(fileName);

    if (!sanitized || sanitized !== fileName || path.extname(sanitized).toLowerCase() !== extension) {
        throw Object.assign(new Error('Invalid file name'), { status: 400 });
    }

    return sanitized;
}

/**
 * Gets a safe character avatar file name.
 * @param {import('express').Request} request Express request
 * @returns {string} Avatar file name
 */
function getAvatarFileName(request) {
    return getSafeFileName(request.params.avatar, '.png');
}

/**
 * Gets a safe chat file name.
 * @param {string} chatId Chat identifier or file name
 * @returns {string} Chat file name
 */
function getChatFileName(chatId) {
    return getSafeFileName(chatId, CHAT_EXTENSION);
}

/**
 * Gets a safe world info file name.
 * @param {string} worldName World info name or file name
 * @returns {string} World info file name
 */
function getWorldFileName(worldName) {
    return getSafeFileName(worldName, WORLD_EXTENSION);
}

/**
 * Creates a URL for an existing thumbnail endpoint.
 * @param {'avatar'|'bg'|'persona'} type Thumbnail type
 * @param {string} file File name
 * @param {boolean} [animated] Whether animated originals should be served
 * @returns {string} Thumbnail URL
 */
function getThumbnailUrl(type, file, animated = false) {
    const params = new URLSearchParams({ type, file });
    if (animated) {
        params.set('animated', 'true');
    }
    return `/thumbnail?${params.toString()}`;
}

/**
 * Adds stable media URLs to a character object.
 * @param {object} character Character data
 * @returns {object} Character data with headless helper URLs
 */
function decorateCharacter(character) {
    if (!character || typeof character !== 'object' || !character.avatar) {
        return character;
    }

    return {
        ...character,
        headless: {
            avatar_url: `/characters/${encodeURIComponent(character.avatar)}`,
            thumbnail_url: getThumbnailUrl('avatar', character.avatar),
        },
    };
}

/**
 * Gets the chat directory for a character avatar.
 * @param {import('../users.js').UserDirectoryList} directories User directories
 * @param {string} avatar Avatar file name
 * @returns {string} Character chat directory
 */
function getCharacterChatDirectory(directories, avatar) {
    const characterDirectory = path.parse(avatar).name;
    const chatDirectory = path.join(directories.chats, characterDirectory);

    if (!isPathUnderParent(directories.chats, chatDirectory)) {
        throw Object.assign(new Error('Invalid character chat directory'), { status: 400 });
    }

    return chatDirectory;
}

/**
 * Resolves a character chat file path.
 * @param {import('../users.js').UserDirectoryList} directories User directories
 * @param {string} avatar Avatar file name
 * @param {string} chatId Chat identifier or file name
 * @returns {{chatDirectory: string, chatFileName: string, chatFilePath: string}} Resolved chat paths
 */
function getCharacterChatPath(directories, avatar, chatId) {
    const chatDirectory = getCharacterChatDirectory(directories, avatar);
    const chatFileName = getChatFileName(chatId);
    const chatFilePath = path.join(chatDirectory, chatFileName);

    if (!isPathUnderParent(directories.chats, chatFilePath)) {
        throw Object.assign(new Error('Invalid chat file path'), { status: 400 });
    }

    return { chatDirectory, chatFileName, chatFilePath };
}

/**
 * Resolves a group chat file path.
 * @param {import('../users.js').UserDirectoryList} directories User directories
 * @param {string} chatId Chat identifier or file name
 * @returns {{chatFileName: string, chatFilePath: string}} Resolved group chat paths
 */
function getGroupChatPath(directories, chatId) {
    const chatFileName = getChatFileName(chatId);
    const chatFilePath = path.join(directories.groupChats, chatFileName);

    if (!isPathUnderParent(directories.groupChats, chatFilePath)) {
        throw Object.assign(new Error('Invalid group chat file path'), { status: 400 });
    }

    return { chatFileName, chatFilePath };
}

/**
 * Returns a normalized chat array with a metadata header.
 * @param {unknown} body Request body
 * @returns {object[]} Chat entries
 */
function normalizeChatPayload(body) {
    const source = Array.isArray(body) ? body : body?.messages ?? body?.chat;

    if (!Array.isArray(source)) {
        throw Object.assign(new Error('Expected a chat array or a body with messages/chat array'), { status: 400 });
    }

    const chat = source.map(entry => ({ ...entry }));
    const metadata = body && typeof body === 'object' && !Array.isArray(body)
        ? body.metadata ?? body.chat_metadata ?? {}
        : {};

    if (!chat[0]?.chat_metadata) {
        chat.unshift({
            chat_metadata: metadata,
            user_name: 'unused',
            character_name: 'unused',
        });
    } else if (metadata && typeof metadata === 'object') {
        chat[0].chat_metadata = {
            ...chat[0].chat_metadata,
            ...metadata,
        };
    }

    return chat;
}

/**
 * Creates a single chat message from a headless request body.
 * @param {unknown} body Request body
 * @returns {object} Chat message
 */
function normalizeChatMessage(body) {
    const message = body?.message && typeof body.message === 'object' ? body.message : body;

    if (!message || typeof message !== 'object') {
        throw Object.assign(new Error('Expected a message object'), { status: 400 });
    }

    return {
        name: String(message.name ?? (message.is_user ? 'User' : 'Assistant')),
        is_user: !!message.is_user,
        send_date: message.send_date ?? new Date().toISOString(),
        mes: String(message.mes ?? ''),
        extra: message.extra && typeof message.extra === 'object' ? message.extra : {},
    };
}

/**
 * Reads all groups with lightweight chat stats.
 * @param {import('../users.js').UserDirectoryList} directories User directories
 * @returns {Promise<object[]>} Groups
 */
async function readGroups(directories) {
    await fs.promises.mkdir(directories.groups, { recursive: true });
    await fs.promises.mkdir(directories.groupChats, { recursive: true });

    const groups = [];
    const files = (await fs.promises.readdir(directories.groups, { withFileTypes: true }))
        .filter(file => file.isFile() && path.extname(file.name).toLowerCase() === WORLD_EXTENSION);
    const groupChats = (await fs.promises.readdir(directories.groupChats, { withFileTypes: true }))
        .filter(file => file.isFile() && path.extname(file.name).toLowerCase() === CHAT_EXTENSION)
        .map(file => file.name);

    for (const file of files) {
        try {
            const filePath = path.join(directories.groups, file.name);
            const group = tryParse(await fs.promises.readFile(filePath, 'utf8'));
            if (!group || typeof group !== 'object') {
                continue;
            }

            const groupStat = await fs.promises.stat(filePath);
            let chatSize = 0;
            let dateLastChat = 0;

            if (Array.isArray(group.chats)) {
                for (const chat of groupChats) {
                    if (!group.chats.includes(path.parse(chat).name)) {
                        continue;
                    }
                    const chatStat = await fs.promises.stat(path.join(directories.groupChats, chat));
                    chatSize += chatStat.size;
                    dateLastChat = Math.max(dateLastChat, chatStat.mtimeMs);
                }
            }

            groups.push({
                ...group,
                file_id: path.parse(file.name).name,
                date_added: groupStat.birthtimeMs,
                create_date: group.create_date ?? new Date(groupStat.birthtimeMs).toISOString(),
                date_last_chat: dateLastChat,
                chat_size: chatSize,
            });
        } catch (error) {
            console.warn('[Headless] Failed to read group:', file.name, error);
        }
    }

    return groups;
}

/**
 * Lists world info files.
 * @param {import('../users.js').UserDirectoryList} directories User directories
 * @returns {Promise<object[]>} World info summaries
 */
async function readWorlds(directories) {
    const files = (await fs.promises.readdir(directories.worlds, { withFileTypes: true }))
        .filter(file => file.isFile() && path.extname(file.name).toLowerCase() === WORLD_EXTENSION)
        .sort((a, b) => a.name.localeCompare(b.name));

    const worlds = [];
    for (const file of files) {
        const filePath = path.join(directories.worlds, file.name);
        const parsed = tryParse(await fs.promises.readFile(filePath, 'utf8')) ?? {};
        const stat = await fs.promises.stat(filePath);
        worlds.push({
            file_id: path.parse(file.name).name,
            name: parsed.name || path.parse(file.name).name,
            entries_count: parsed.entries && typeof parsed.entries === 'object' ? Object.keys(parsed.entries).length : 0,
            extensions: parsed.extensions && typeof parsed.extensions === 'object' ? parsed.extensions : {},
            updated_at: stat.mtimeMs,
        });
    }

    return worlds;
}

router.get('/bootstrap', asyncRoute(async (request, response) => {
    const remoteApp = getHeadlessRemoteConfig();

    response.json({
        version: HEADLESS_API_VERSION,
        user: {
            handle: request.user.profile.handle,
            name: request.user.profile.name,
            avatar: request.user.profile.avatar,
        },
        remoteApp,
        urls: {
            app: '/headless/',
            csrf: '/csrf-token',
            api: '/api/headless/v1',
            avatar_thumbnail: '/thumbnail?type=avatar&file={avatar}',
            background_thumbnail: '/thumbnail?type=bg&file={background}&animated=true',
        },
        features: {
            characters: ['list', 'get', 'patch'],
            chats: ['list', 'get', 'create', 'replace', 'append-message', 'delete'],
            groups: ['list', 'get', 'get-chat', 'replace-chat'],
            worlds: ['list', 'get', 'replace', 'delete'],
            backgrounds: ['list'],
        },
    });
}));

router.get('/library', asyncRoute(async (request, response) => {
    const [characters, groups, worlds] = await Promise.all([
        fs.promises.readdir(request.user.directories.characters)
            .then(files => Promise.all(files
                .filter(file => path.extname(file).toLowerCase() === '.png')
                .map(file => processCharacter(file, request.user.directories, { shallow: true }))))
            .then(items => items.filter(character => character.name).map(decorateCharacter)),
        readGroups(request.user.directories),
        readWorlds(request.user.directories),
    ]);

    const backgrounds = getImages(request.user.directories.backgrounds).map(filename => ({
        filename,
        url: `/backgrounds/${encodeURIComponent(filename)}`,
        thumbnail_url: getThumbnailUrl('bg', filename, true),
    }));

    response.json({ characters, groups, worlds, backgrounds });
}));

router.get('/characters', asyncRoute(async (request, response) => {
    const full = request.query.full === 'true';
    const files = await fs.promises.readdir(request.user.directories.characters);
    const characters = await Promise.all(files
        .filter(file => path.extname(file).toLowerCase() === '.png')
        .map(file => processCharacter(file, request.user.directories, { shallow: !full })));

    response.json({ items: characters.filter(character => character.name).map(decorateCharacter) });
}));

router.get('/characters/:avatar', asyncRoute(async (request, response) => {
    const avatar = getAvatarFileName(request);
    const avatarPath = path.join(request.user.directories.characters, avatar);
    if (!fs.existsSync(avatarPath)) {
        return response.sendStatus(404);
    }

    const character = await processCharacter(avatar, request.user.directories, { shallow: false });
    response.json({ character: decorateCharacter(character) });
}));

router.patch('/characters/:avatar', asyncRoute(async (request, response) => {
    const avatar = getAvatarFileName(request);
    const avatarPath = path.join(request.user.directories.characters, avatar);
    if (!fs.existsSync(avatarPath)) {
        return response.sendStatus(404);
    }

    const update = request.body?.patch && Object.keys(request.body).length === 1 ? request.body.patch : request.body;
    const result = await mergeCharacterUpdate(avatarPath, avatar, { avatar, ...update }, request);
    if (!result.ok) {
        return response.status(400).json({ ok: false, error: result.error ?? 'Character validation failed' });
    }

    const character = await processCharacter(avatar, request.user.directories, { shallow: false });
    response.json({ ok: true, character: decorateCharacter(character) });
}));

router.get('/characters/:avatar/chats', asyncRoute(async (request, response) => {
    const avatar = getAvatarFileName(request);
    const chatDirectory = getCharacterChatDirectory(request.user.directories, avatar);
    if (!fs.existsSync(chatDirectory)) {
        return response.json({ items: [] });
    }

    const files = (await fs.promises.readdir(chatDirectory, { withFileTypes: true }))
        .filter(file => file.isFile() && path.extname(file.name).toLowerCase() === CHAT_EXTENSION)
        .map(file => file.name);
    const items = await Promise.all(files.map(file => getChatInfo(path.join(chatDirectory, file), {}, true)));
    response.json({ items: items.filter(item => item.file_name) });
}));

router.post('/characters/:avatar/chats', asyncRoute(async (request, response) => {
    const avatar = getAvatarFileName(request);
    const chatId = request.body?.id || request.body?.file_name || humanizedDateTime();
    const { chatDirectory, chatFileName, chatFilePath } = getCharacterChatPath(request.user.directories, avatar, chatId);
    await fs.promises.mkdir(chatDirectory, { recursive: true });

    if (fs.existsSync(chatFilePath) && !request.body?.overwrite) {
        return response.status(409).json({ error: 'Chat already exists', file_name: chatFileName });
    }

    const chat = normalizeChatPayload(request.body?.messages ? request.body : { messages: [] });
    const cardName = path.parse(avatar).name;
    await trySaveChat(chat, chatFilePath, request.body?.force, request.user.profile.handle, cardName, request.user.directories.backups);
    response.status(201).json({ ok: true, file_name: chatFileName, file_id: path.parse(chatFileName).name, messages: chat });
}));

router.get('/characters/:avatar/chats/:chatId', asyncRoute(async (request, response) => {
    const avatar = getAvatarFileName(request);
    const { chatFileName, chatFilePath } = getCharacterChatPath(request.user.directories, avatar, request.params.chatId);

    if (!fs.existsSync(chatFilePath)) {
        return response.sendStatus(404);
    }

    response.json({
        file_name: chatFileName,
        file_id: path.parse(chatFileName).name,
        messages: getChatData(chatFilePath),
    });
}));

router.put('/characters/:avatar/chats/:chatId', asyncRoute(async (request, response) => {
    const avatar = getAvatarFileName(request);
    const { chatDirectory, chatFileName, chatFilePath } = getCharacterChatPath(request.user.directories, avatar, request.params.chatId);
    await fs.promises.mkdir(chatDirectory, { recursive: true });

    const chat = normalizeChatPayload(request.body);
    const cardName = path.parse(avatar).name;
    await trySaveChat(chat, chatFilePath, request.body?.force, request.user.profile.handle, cardName, request.user.directories.backups);
    response.json({ ok: true, file_name: chatFileName, file_id: path.parse(chatFileName).name, messages: chat });
}));

router.post('/characters/:avatar/chats/:chatId/messages', asyncRoute(async (request, response) => {
    const avatar = getAvatarFileName(request);
    const { chatDirectory, chatFileName, chatFilePath } = getCharacterChatPath(request.user.directories, avatar, request.params.chatId);
    await fs.promises.mkdir(chatDirectory, { recursive: true });

    const existingChat = fs.existsSync(chatFilePath)
        ? getChatData(chatFilePath)
        : normalizeChatPayload({ messages: [] });
    const message = normalizeChatMessage(request.body);
    const nextChat = [...existingChat, message];
    const cardName = path.parse(avatar).name;
    await trySaveChat(nextChat, chatFilePath, request.body?.force, request.user.profile.handle, cardName, request.user.directories.backups);
    response.status(201).json({ ok: true, file_name: chatFileName, file_id: path.parse(chatFileName).name, message, messages: nextChat });
}));

router.delete('/characters/:avatar/chats/:chatId', asyncRoute(async (request, response) => {
    const avatar = getAvatarFileName(request);
    const { chatFilePath } = getCharacterChatPath(request.user.directories, avatar, request.params.chatId);

    if (!fs.existsSync(chatFilePath)) {
        return response.sendStatus(404);
    }

    response.json({ ok: tryDeleteFile(chatFilePath) });
}));

router.get('/groups', asyncRoute(async (request, response) => {
    response.json({ items: await readGroups(request.user.directories) });
}));

router.get('/groups/:groupId', asyncRoute(async (request, response) => {
    const groupId = path.parse(getWorldFileName(request.params.groupId)).name;
    const groupPath = path.join(request.user.directories.groups, `${groupId}.json`);
    if (!fs.existsSync(groupPath)) {
        return response.sendStatus(404);
    }

    response.json({ group: tryParse(await fs.promises.readFile(groupPath, 'utf8')) });
}));

router.get('/groups/:groupId/chats/:chatId', asyncRoute(async (request, response) => {
    const { chatFileName, chatFilePath } = getGroupChatPath(request.user.directories, request.params.chatId);
    if (!fs.existsSync(chatFilePath)) {
        return response.sendStatus(404);
    }

    response.json({
        file_name: chatFileName,
        file_id: path.parse(chatFileName).name,
        messages: getChatData(chatFilePath),
    });
}));

router.put('/groups/:groupId/chats/:chatId', asyncRoute(async (request, response) => {
    const groupId = path.parse(getWorldFileName(request.params.groupId)).name;
    const groupPath = path.join(request.user.directories.groups, `${groupId}.json`);
    if (!fs.existsSync(groupPath)) {
        return response.sendStatus(404);
    }

    const { chatFileName, chatFilePath } = getGroupChatPath(request.user.directories, request.params.chatId);
    const chat = normalizeChatPayload(request.body);
    await trySaveChat(chat, chatFilePath, request.body?.force, request.user.profile.handle, groupId, request.user.directories.backups);
    response.json({ ok: true, file_name: chatFileName, file_id: path.parse(chatFileName).name, messages: chat });
}));

router.get('/worlds', asyncRoute(async (request, response) => {
    response.json({ items: await readWorlds(request.user.directories) });
}));

router.get('/worlds/:name', asyncRoute(async (request, response) => {
    const worldName = path.parse(getWorldFileName(request.params.name)).name;
    const world = readWorldInfoFile(request.user.directories, worldName, false);
    if (!world) {
        return response.sendStatus(404);
    }

    response.json({ name: worldName, data: world });
}));

router.put('/worlds/:name', asyncRoute(async (request, response) => {
    const worldFileName = getWorldFileName(request.params.name);
    const worldName = path.parse(worldFileName).name;
    const data = request.body?.data ?? request.body;

    if (!data || typeof data !== 'object' || !('entries' in data)) {
        return response.status(400).json({ error: 'World info data must contain entries' });
    }

    const worldPath = path.join(request.user.directories.worlds, worldFileName);
    writeFileAtomicSync(worldPath, JSON.stringify(data, null, 4));
    response.json({ ok: true, name: worldName, data });
}));

router.delete('/worlds/:name', asyncRoute(async (request, response) => {
    const worldPath = path.join(request.user.directories.worlds, getWorldFileName(request.params.name));
    if (!fs.existsSync(worldPath)) {
        return response.sendStatus(404);
    }

    fs.unlinkSync(worldPath);
    response.json({ ok: true });
}));

router.get('/backgrounds', asyncRoute(async (request, response) => {
    const items = getImages(request.user.directories.backgrounds).map(filename => ({
        filename,
        url: `/backgrounds/${encodeURIComponent(filename)}`,
        thumbnail_url: getThumbnailUrl('bg', filename, true),
    }));

    response.json({ items });
}));

router.use((error, _request, response, _next) => {
    const status = Number.isInteger(error?.status) ? error.status : 500;
    if (status >= 500) {
        console.error('[Headless] API error:', error);
    }
    response.status(status).json({ error: error?.message ?? 'Headless API request failed' });
});
