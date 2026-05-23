const API_ROOT = '/api/headless/v1';
const CACHE_KEY = 'sillytavern-headless-cache-v1';

const state = {
    csrfToken: '',
    bootstrap: null,
    characters: [],
    groups: [],
    worlds: [],
    backgrounds: [],
    selectedAvatar: '',
    currentCharacter: null,
    chats: [],
    selectedChatId: '',
    messages: [],
    activeTab: 'card',
    dirty: false,
};

const els = {
    userLine: document.getElementById('userLine'),
    characterSearch: document.getElementById('characterSearch'),
    characterList: document.getElementById('characterList'),
    selectedAvatar: document.getElementById('selectedAvatar'),
    selectedKicker: document.getElementById('selectedKicker'),
    selectedName: document.getElementById('selectedName'),
    characterForm: document.getElementById('characterForm'),
    chatList: document.getElementById('chatList'),
    chatTitle: document.getElementById('chatTitle'),
    messageList: document.getElementById('messageList'),
    toast: document.getElementById('toast'),
};

function escapeHtml(value) {
    return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll('\'', '&#39;');
}

function encodePath(value) {
    return encodeURIComponent(String(value ?? ''));
}

function compactText(value, fallback = '') {
    return String(value ?? fallback).replace(/\s+/g, ' ').trim();
}

function toTags(value) {
    if (Array.isArray(value)) {
        return value.map(item => String(item).trim()).filter(Boolean);
    }
    return String(value ?? '').split(',').map(item => item.trim()).filter(Boolean);
}

function showToast(message) {
    els.toast.textContent = message;
    els.toast.classList.add('visible');
    window.clearTimeout(showToast.timer);
    showToast.timer = window.setTimeout(() => els.toast.classList.remove('visible'), 2200);
}

function loadCache() {
    try {
        const cached = JSON.parse(localStorage.getItem(CACHE_KEY) || '{}');
        if (!cached || typeof cached !== 'object') {
            return;
        }
        state.characters = Array.isArray(cached.characters) ? cached.characters : [];
        state.groups = Array.isArray(cached.groups) ? cached.groups : [];
        state.worlds = Array.isArray(cached.worlds) ? cached.worlds : [];
        state.backgrounds = Array.isArray(cached.backgrounds) ? cached.backgrounds : [];
        state.selectedAvatar = cached.selectedAvatar || '';
    } catch {
        localStorage.removeItem(CACHE_KEY);
    }
}

function saveCache() {
    const payload = {
        characters: state.characters,
        groups: state.groups,
        worlds: state.worlds,
        backgrounds: state.backgrounds,
        selectedAvatar: state.selectedAvatar,
        savedAt: Date.now(),
    };
    localStorage.setItem(CACHE_KEY, JSON.stringify(payload));
}

async function getCsrfToken() {
    const response = await fetch('/csrf-token', { credentials: 'include' });
    if (!response.ok) {
        throw new Error('Unable to get CSRF token');
    }
    const data = await response.json();
    state.csrfToken = data.token;
}

async function api(path, options = {}) {
    const method = options.method || 'GET';
    const headers = new Headers(options.headers || {});
    const init = {
        method,
        credentials: 'include',
        headers,
    };

    if (method !== 'GET' && method !== 'HEAD') {
        headers.set('content-type', 'application/json');
        headers.set('x-csrf-token', state.csrfToken);
        init.body = JSON.stringify(options.body ?? {});
    }

    const response = await fetch(`${API_ROOT}${path}`, init);
    if (response.status === 403) {
        window.location.href = `/login?return=${encodeURIComponent('/headless/')}`;
        return null;
    }

    const contentType = response.headers.get('content-type') || '';
    const payload = contentType.includes('application/json') ? await response.json() : await response.text();

    if (!response.ok) {
        const message = typeof payload === 'object' ? payload.error || payload.message : payload;
        throw new Error(message || `Request failed with ${response.status}`);
    }

    return payload;
}

async function refreshLibrary({ preserveSelection = true } = {}) {
    const [bootstrap, library] = await Promise.all([
        api('/bootstrap'),
        api('/library'),
    ]);

    if (!bootstrap || !library) {
        return;
    }

    state.bootstrap = bootstrap;
    state.characters = library.characters || [];
    state.groups = library.groups || [];
    state.worlds = library.worlds || [];
    state.backgrounds = library.backgrounds || [];
    els.userLine.textContent = bootstrap.user?.name || bootstrap.user?.handle || 'Local user';

    if (!preserveSelection || !state.characters.some(character => character.avatar === state.selectedAvatar)) {
        state.selectedAvatar = state.characters[0]?.avatar || '';
    }

    saveCache();
    renderCharacters();

    if (state.selectedAvatar) {
        await selectCharacter(state.selectedAvatar);
    } else {
        renderSelection();
        renderForm();
        renderChats();
    }
}

async function selectCharacter(avatar) {
    state.selectedAvatar = avatar;
    state.selectedChatId = '';
    state.messages = [];
    const [characterData, chatsData] = await Promise.all([
        api(`/characters/${encodePath(avatar)}`),
        api(`/characters/${encodePath(avatar)}/chats`),
    ]);

    state.currentCharacter = characterData?.character || null;
    state.chats = chatsData?.items || [];
    state.selectedChatId = state.chats[0]?.file_id || '';
    state.dirty = false;
    saveCache();
    renderAll();

    if (state.selectedChatId) {
        await selectChat(state.selectedChatId);
    }
}

async function selectChat(chatId) {
    if (!state.selectedAvatar || !chatId) {
        return;
    }
    const data = await api(`/characters/${encodePath(state.selectedAvatar)}/chats/${encodePath(chatId)}`);
    state.selectedChatId = data.file_id;
    state.messages = Array.isArray(data.messages) ? data.messages : [];
    renderChats();
}

function renderAll() {
    renderCharacters();
    renderSelection();
    renderTabs();
    renderForm();
    renderChats();
}

function renderCharacters() {
    const query = els.characterSearch.value.trim().toLowerCase();
    const characters = state.characters.filter(character => {
        const tags = character.data?.tags || character.tags || [];
        return [
            character.name,
            character.data?.creator,
            Array.isArray(tags) ? tags.join(' ') : tags,
        ].some(value => String(value ?? '').toLowerCase().includes(query));
    });

    if (!characters.length) {
        els.characterList.innerHTML = '<div class="empty-state">No characters</div>';
        return;
    }

    els.characterList.innerHTML = characters.map(character => {
        const tags = character.data?.tags || character.tags || [];
        const tagText = Array.isArray(tags) ? tags.slice(0, 4).join(', ') : tags;
        const active = character.avatar === state.selectedAvatar ? ' active' : '';
        return `
            <button type="button" class="character-card${active}" data-avatar="${escapeHtml(character.avatar)}">
                <img src="${escapeHtml(character.headless?.thumbnail_url || '/img/No-Image-Placeholder.svg')}" alt="">
                <span>
                    <strong>${escapeHtml(character.name || 'Unnamed')}</strong>
                    <span>${escapeHtml(tagText || compactText(character.description, 'No tags'))}</span>
                </span>
            </button>
        `;
    }).join('');
}

function renderSelection() {
    const character = state.currentCharacter;
    els.selectedAvatar.src = character?.headless?.thumbnail_url || '/img/No-Image-Placeholder.svg';
    els.selectedKicker.textContent = character?.data?.creator ? character.data.creator : 'Character card';
    els.selectedName.textContent = character?.name || 'No character selected';
}

function renderTabs() {
    document.querySelectorAll('.tab-button').forEach(button => {
        button.classList.toggle('active', button.dataset.tab === state.activeTab);
        button.setAttribute('aria-selected', String(button.dataset.tab === state.activeTab));
    });
}

function getCharacterValues() {
    const character = state.currentCharacter || {};
    const data = character.data || {};
    const extensions = data.extensions || {};
    const depthPrompt = extensions.depth_prompt || {};
    return {
        name: data.name || character.name || '',
        description: data.description || character.description || '',
        personality: data.personality || character.personality || '',
        scenario: data.scenario || character.scenario || '',
        first_mes: data.first_mes || character.first_mes || '',
        mes_example: data.mes_example || character.mes_example || '',
        creator_notes: data.creator_notes || character.creatorcomment || '',
        system_prompt: data.system_prompt || '',
        post_history_instructions: data.post_history_instructions || '',
        creator: data.creator || character.creator || '',
        character_version: data.character_version || '',
        tags: Array.isArray(data.tags) ? data.tags.join(', ') : Array.isArray(character.tags) ? character.tags.join(', ') : character.tags || '',
        fav: Boolean(extensions.fav || character.fav),
        talkativeness: Number(extensions.talkativeness || character.talkativeness || 0.5),
        world: extensions.world || '',
        depth_prompt_prompt: depthPrompt.prompt || '',
        depth_prompt_depth: Number(depthPrompt.depth || 4),
        depth_prompt_role: depthPrompt.role || 'system',
        alternate_greetings: Array.isArray(data.alternate_greetings) ? data.alternate_greetings.join('\n') : '',
    };
}

function renderForm() {
    if (!state.currentCharacter) {
        els.characterForm.innerHTML = '<div class="empty-state">No card loaded</div>';
        return;
    }

    const values = getCharacterValues();
    const worldOptions = [
        '<option value="">None</option>',
        ...state.worlds.map(world => `<option value="${escapeHtml(world.file_id)}" ${world.file_id === values.world ? 'selected' : ''}>${escapeHtml(world.name || world.file_id)}</option>`),
    ].join('');

    if (state.activeTab === 'card') {
        els.characterForm.innerHTML = `
            <div class="form-grid">
                ${field('Name', 'name', values.name)}
                ${field('Creator', 'creator', values.creator)}
                ${field('Version', 'character_version', values.character_version)}
                ${field('Tags', 'tags', values.tags)}
                <label class="field inline wide">
                    <input type="checkbox" name="fav" ${values.fav ? 'checked' : ''}>
                    <span>Favorite</span>
                </label>
                <label class="field wide">
                    <span>Talkativeness</span>
                    <span class="range-row">
                        <input type="range" min="0" max="1" step="0.05" name="talkativeness" value="${escapeHtml(values.talkativeness)}">
                        <output>${escapeHtml(values.talkativeness.toFixed(2))}</output>
                    </span>
                </label>
                ${textarea('Creator notes', 'creator_notes', values.creator_notes, true)}
            </div>
        `;
        return;
    }

    if (state.activeTab === 'prompts') {
        els.characterForm.innerHTML = `
            <div class="form-grid">
                ${textarea('Description', 'description', values.description, true)}
                ${textarea('Personality', 'personality', values.personality, true)}
                ${textarea('Scenario', 'scenario', values.scenario, true)}
                ${textarea('First message', 'first_mes', values.first_mes, true)}
                ${textarea('Message example', 'mes_example', values.mes_example, true)}
                ${textarea('System prompt', 'system_prompt', values.system_prompt, true)}
                ${textarea('Post history instructions', 'post_history_instructions', values.post_history_instructions, true)}
                ${textarea('Alternate greetings', 'alternate_greetings', values.alternate_greetings, true)}
            </div>
        `;
        return;
    }

    if (state.activeTab === 'extensions') {
        els.characterForm.innerHTML = `
            <div class="form-grid">
                <label class="field wide">
                    <span>World</span>
                    <select name="world">${worldOptions}</select>
                </label>
                ${textarea('Depth prompt', 'depth_prompt_prompt', values.depth_prompt_prompt, true)}
                ${field('Depth', 'depth_prompt_depth', values.depth_prompt_depth, 'number')}
                <label class="field">
                    <span>Depth role</span>
                    <select name="depth_prompt_role">
                        ${['system', 'user', 'assistant'].map(role => `<option value="${role}" ${role === values.depth_prompt_role ? 'selected' : ''}>${role}</option>`).join('')}
                    </select>
                </label>
            </div>
        `;
        return;
    }

    els.characterForm.innerHTML = `
        <div class="asset-grid">
            ${state.backgrounds.map(item => `
                <div class="asset-item">
                    <img src="${escapeHtml(item.thumbnail_url)}" alt="">
                    <span>${escapeHtml(item.filename)}</span>
                </div>
            `).join('') || '<div class="empty-state">No backgrounds</div>'}
        </div>
    `;
}

function field(label, name, value, type = 'text') {
    return `
        <label class="field">
            <span>${escapeHtml(label)}</span>
            <input type="${escapeHtml(type)}" name="${escapeHtml(name)}" value="${escapeHtml(value)}">
        </label>
    `;
}

function textarea(label, name, value, wide = false) {
    return `
        <label class="field ${wide ? 'wide' : ''}">
            <span>${escapeHtml(label)}</span>
            <textarea name="${escapeHtml(name)}">${escapeHtml(value)}</textarea>
        </label>
    `;
}

function renderChats() {
    if (!state.currentCharacter) {
        els.chatTitle.textContent = 'No chat loaded';
        els.chatList.innerHTML = '';
        els.messageList.innerHTML = '<div class="empty-state">No messages</div>';
        return;
    }

    els.chatList.innerHTML = state.chats.length
        ? state.chats.map(chat => `
            <button type="button" class="chat-pill ${chat.file_id === state.selectedChatId ? 'active' : ''}" data-chat="${escapeHtml(chat.file_id)}">
                ${escapeHtml(chat.file_id)}
            </button>
        `).join('')
        : '<div class="empty-state">No chats</div>';

    els.chatTitle.textContent = state.selectedChatId || 'No chat loaded';
    const editableMessages = state.messages
        .map((message, index) => ({ message, index }))
        .filter(item => !item.message.chat_metadata);

    if (!editableMessages.length) {
        els.messageList.innerHTML = '<div class="empty-state">No messages</div>';
        return;
    }

    els.messageList.innerHTML = editableMessages.map(({ message, index }) => {
        const isUser = Boolean(message.is_user);
        return `
            <article class="message-card ${isUser ? 'user' : 'assistant'}" data-message-index="${index}">
                <div class="message-meta">
                    <label>
                        <span>Role</span>
                        <select data-message-field="is_user">
                            <option value="true" ${isUser ? 'selected' : ''}>user</option>
                            <option value="false" ${!isUser ? 'selected' : ''}>assistant</option>
                        </select>
                    </label>
                    <label>
                        <span>Name</span>
                        <input data-message-field="name" value="${escapeHtml(message.name || '')}">
                    </label>
                    <button type="button" class="icon-button" data-action="remove-message" title="Remove message" aria-label="Remove message">
                        <i class="fa-solid fa-trash" aria-hidden="true"></i>
                    </button>
                </div>
                <textarea data-message-field="mes">${escapeHtml(message.mes || '')}</textarea>
            </article>
        `;
    }).join('');
}

function collectCharacterPatch() {
    const base = getCharacterValues();
    const formData = new FormData(els.characterForm);
    const values = { ...base, ...Object.fromEntries(formData.entries()) };
    const tags = toTags(values.tags);
    const fav = els.characterForm.elements.fav ? els.characterForm.elements.fav.checked : base.fav;
    const talkativeness = Number(values.talkativeness ?? base.talkativeness);
    const alternateGreetings = String(values.alternate_greetings ?? '')
        .split('\n')
        .map(item => item.trim())
        .filter(Boolean);

    return {
        name: values.name,
        description: values.description,
        personality: values.personality,
        scenario: values.scenario,
        first_mes: values.first_mes,
        mes_example: values.mes_example,
        creatorcomment: values.creator_notes,
        creator: values.creator,
        tags,
        fav,
        talkativeness,
        data: {
            name: values.name,
            description: values.description,
            personality: values.personality,
            scenario: values.scenario,
            first_mes: values.first_mes,
            mes_example: values.mes_example,
            creator_notes: values.creator_notes,
            system_prompt: values.system_prompt,
            post_history_instructions: values.post_history_instructions,
            creator: values.creator,
            character_version: values.character_version,
            tags,
            alternate_greetings: alternateGreetings,
            extensions: {
                ...(state.currentCharacter?.data?.extensions || {}),
                fav,
                talkativeness,
                world: values.world,
                depth_prompt: {
                    prompt: values.depth_prompt_prompt,
                    depth: Number(values.depth_prompt_depth || 4),
                    role: values.depth_prompt_role || 'system',
                },
            },
        },
    };
}

function collectChatMessages() {
    const header = state.messages[0]?.chat_metadata
        ? { ...state.messages[0] }
        : { chat_metadata: {}, user_name: 'unused', character_name: 'unused' };
    const messages = [header];

    els.messageList.querySelectorAll('.message-card').forEach(card => {
        const isUser = card.querySelector('[data-message-field="is_user"]').value === 'true';
        messages.push({
            name: card.querySelector('[data-message-field="name"]').value,
            is_user: isUser,
            send_date: state.messages[Number(card.dataset.messageIndex)]?.send_date || new Date().toISOString(),
            mes: card.querySelector('[data-message-field="mes"]').value,
            extra: state.messages[Number(card.dataset.messageIndex)]?.extra || {},
        });
    });

    return messages;
}

async function saveCharacter() {
    if (!state.selectedAvatar || !state.currentCharacter) {
        showToast('No character selected');
        return;
    }
    const payload = collectCharacterPatch();
    const data = await api(`/characters/${encodePath(state.selectedAvatar)}`, {
        method: 'PATCH',
        body: payload,
    });
    state.currentCharacter = data.character;
    const index = state.characters.findIndex(character => character.avatar === state.selectedAvatar);
    if (index >= 0) {
        state.characters[index] = {
            ...state.characters[index],
            name: data.character.name,
            data: data.character.data,
        };
    }
    state.dirty = false;
    saveCache();
    renderAll();
    showToast('Character saved');
}

async function createChat() {
    if (!state.selectedAvatar) {
        showToast('No character selected');
        return;
    }
    const data = await api(`/characters/${encodePath(state.selectedAvatar)}/chats`, {
        method: 'POST',
        body: { messages: [] },
    });
    state.chats = [{ file_id: data.file_id, file_name: data.file_name }, ...state.chats];
    state.selectedChatId = data.file_id;
    state.messages = data.messages || [];
    renderChats();
    showToast('Chat created');
}

async function saveChat() {
    if (!state.selectedAvatar || !state.selectedChatId) {
        showToast('No chat selected');
        return;
    }
    const messages = collectChatMessages();
    const data = await api(`/characters/${encodePath(state.selectedAvatar)}/chats/${encodePath(state.selectedChatId)}`, {
        method: 'PUT',
        body: { messages, force: true },
    });
    state.messages = data.messages || messages;
    renderChats();
    showToast('Chat saved');
}

function addMessage(isUser) {
    if (!state.messages.length) {
        state.messages = [{ chat_metadata: {}, user_name: 'unused', character_name: 'unused' }];
    }
    state.messages.push({
        name: isUser ? 'User' : state.currentCharacter?.name || 'Assistant',
        is_user: isUser,
        send_date: new Date().toISOString(),
        mes: '',
        extra: {},
    });
    renderChats();
}

function removeMessage(button) {
    const card = button.closest('.message-card');
    const index = Number(card?.dataset.messageIndex);
    if (!Number.isInteger(index)) {
        return;
    }
    state.messages.splice(index, 1);
    renderChats();
}

document.addEventListener('click', async (event) => {
    const characterButton = event.target.closest('[data-avatar]');
    if (characterButton) {
        try {
            await selectCharacter(characterButton.dataset.avatar);
        } catch (error) {
            showToast(error.message);
        }
        return;
    }

    const chatButton = event.target.closest('[data-chat]');
    if (chatButton) {
        try {
            await selectChat(chatButton.dataset.chat);
        } catch (error) {
            showToast(error.message);
        }
        return;
    }

    const tabButton = event.target.closest('[data-tab]');
    if (tabButton) {
        state.activeTab = tabButton.dataset.tab;
        renderTabs();
        renderForm();
        return;
    }

    const actionButton = event.target.closest('[data-action]');
    if (!actionButton) {
        return;
    }

    const action = actionButton.dataset.action;
    try {
        if (action === 'reload') await refreshLibrary();
        if (action === 'save-character') await saveCharacter();
        if (action === 'new-chat') await createChat();
        if (action === 'save-chat') await saveChat();
        if (action === 'add-user-message') addMessage(true);
        if (action === 'add-assistant-message') addMessage(false);
        if (action === 'remove-message') removeMessage(actionButton);
    } catch (error) {
        showToast(error.message);
    }
});

els.characterSearch.addEventListener('input', renderCharacters);
els.characterForm.addEventListener('input', (event) => {
    state.dirty = true;
    if (event.target.name === 'talkativeness') {
        event.target.closest('.range-row')?.querySelector('output')?.replaceChildren(Number(event.target.value).toFixed(2));
    }
});

window.addEventListener('beforeunload', (event) => {
    if (!state.dirty) {
        return;
    }
    event.preventDefault();
    event.returnValue = '';
});

async function init() {
    loadCache();
    renderCharacters();
    renderSelection();
    renderForm();
    renderChats();

    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('/headless/service-worker.js').catch(() => {});
    }

    try {
        await getCsrfToken();
        await refreshLibrary();
    } catch (error) {
        showToast(error.message);
    }
}

init();
