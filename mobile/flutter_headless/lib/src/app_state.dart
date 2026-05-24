import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

const defaultBackendUrl = String.fromEnvironment(
  'HEADLESS_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
const providerSelectionPrefsKey = 'providerSelection';
const providerApiKeySecureKey = 'providerApiKey';

class AppState extends ChangeNotifier {
  AppState({FlutterSecureStorage? secureStorage})
      : secureStorage = secureStorage ?? const FlutterSecureStorage(),
        api = HeadlessApi(defaultBackendUrl);

  final HeadlessApi api;
  final FlutterSecureStorage secureStorage;
  String serverUrl = defaultBackendUrl;
  bool loading = false;
  String? error;

  HeadlessBootstrap? bootstrap;
  ProviderCatalog? providerCatalog;
  List<CharacterCard> characters = <CharacterCard>[];
  CharacterCard? selectedCharacter;
  List<ChatSummary> chats = <ChatSummary>[];
  ChatSummary? selectedChat;
  List<ChatMessage> messages = <ChatMessage>[];

  String chatSort = 'date';
  bool chatSortAscending = false;
  int loadedOffset = 0;
  int loadedTotal = 0;
  int pageSize = 40;

  bool get hasMoreBefore => loadedOffset > 0;
  ProviderSelection? get currentProvider => providerCatalog?.current;
  ProviderSelection? get serverPresetProvider => providerCatalog?.serverPreset;
  bool get hasLocalProviderOverride {
    final catalog = providerCatalog;
    if (catalog == null) {
      return false;
    }
    return _providerSignature(catalog.current) !=
        _providerSignature(catalog.serverPreset);
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    serverUrl = prefs.getString('serverUrl') ?? defaultBackendUrl;
    api.baseUrl = serverUrl;
    await refresh();
  }

  Future<void> setServerUrl(String value) async {
    serverUrl = value.trim();
    api.baseUrl = serverUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', serverUrl);
    await refresh();
  }

  Future<void> refresh() async {
    await _run(() async {
      final prefs = await SharedPreferences.getInstance();
      final lastAvatar = prefs.getString('lastAvatar');
      bootstrap = await api.bootstrap();
      providerCatalog = _catalogWithLocalProvider(
        await api.providers(),
        await _readLocalProviderSelection(prefs),
      );
      characters = await api.characters(full: false);
      if (characters.isEmpty) {
        selectedCharacter = null;
        chats = <ChatSummary>[];
        selectedChat = null;
        messages = <ChatMessage>[];
        return;
      }

      final initial = characters.firstWhere(
        (character) => character.avatar == lastAvatar,
        orElse: () => characters.first,
      );
      await selectCharacter(initial, persist: false);
    });
  }

  Future<void> selectCharacter(CharacterCard character,
      {bool persist = true}) async {
    selectedCharacter = await api.character(character.avatar);
    messages = <ChatMessage>[];
    selectedChat = null;

    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastAvatar', character.avatar);
    }

    await loadChats(selectLast: true);
    notifyListeners();
  }

  Future<void> loadChats({bool selectLast = false}) async {
    final character = selectedCharacter;
    if (character == null) {
      return;
    }

    chats = await api.chats(character.avatar,
        sort: chatSort, ascending: chatSortAscending);
    if (selectLast && chats.isNotEmpty) {
      await selectChat(chats.first);
    } else if (chats.isEmpty) {
      selectedChat = null;
      messages = <ChatMessage>[];
    }
  }

  Future<void> setChatSort(String sort, bool ascending) async {
    chatSort = sort;
    chatSortAscending = ascending;
    await _run(() async {
      await loadChats(selectLast: selectedChat == null);
    });
  }

  Future<void> selectChat(ChatSummary chat) async {
    final character = selectedCharacter;
    if (character == null) {
      return;
    }

    selectedChat = chat;
    final total = chat.chatItems;
    final offset = max(0, total - pageSize);
    final page = await api.chatPage(character.avatar, chat.fileId,
        offset: offset, limit: pageSize);
    loadedOffset = page.offset;
    loadedTotal = page.total;
    messages = page.messages;
    notifyListeners();
  }

  Future<void> loadOlderMessages() async {
    final character = selectedCharacter;
    final chat = selectedChat;
    if (character == null || chat == null || loadedOffset <= 0) {
      return;
    }

    await _run(() async {
      final nextOffset = max(0, loadedOffset - pageSize);
      final limit = loadedOffset - nextOffset;
      final page = await api.chatPage(character.avatar, chat.fileId,
          offset: nextOffset, limit: limit);
      loadedOffset = page.offset;
      loadedTotal = page.total;
      messages = <ChatMessage>[...page.messages, ...messages];
    });
  }

  Future<void> createNewChat() async {
    final character = selectedCharacter;
    if (character == null) {
      return;
    }

    await _run(() async {
      final page = await api.createChat(character.avatar);
      await loadChats();
      selectedChat = chats.firstWhere(
        (chat) => chat.fileName == page.fileName,
        orElse: () => chats.isNotEmpty
            ? chats.first
            : ChatSummary(
                fileId: page.fileId,
                fileName: page.fileName,
                fileSize: '0 B',
                fileSizeBytes: 0,
                chatItems: 0,
                preview: '',
                lastMessageAt: DateTime.now(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
      );
      messages = <ChatMessage>[];
      loadedOffset = 0;
      loadedTotal = 0;
    });
  }

  Future<void> sendUserMessage(String text) async {
    final character = selectedCharacter;
    if (character == null || text.trim().isEmpty) {
      return;
    }

    await _run(() async {
      ChatSummary? chat = selectedChat;
      if (chat == null) {
        await createNewChat();
        chat = selectedChat;
      }
      if (chat == null) {
        return;
      }

      final page = await api.appendMessage(
        character.avatar,
        chat.fileId,
        name: bootstrap?.userName ?? 'User',
        isUser: true,
        text: text.trim(),
      );
      messages = page.messages;
      loadedOffset = page.offset;
      loadedTotal = page.total;
      await loadChats();
      selectedChat = chats.firstWhere((item) => item.fileName == page.fileName,
          orElse: () => chat!);
    });
  }

  Future<void> startChatWithAssistantMessage(String text,
      {String? name}) async {
    final character = selectedCharacter;
    if (character == null || text.trim().isEmpty) {
      return;
    }

    await _run(() async {
      ChatSummary? chat = selectedChat;
      if (chat == null) {
        await createNewChat();
        chat = selectedChat;
      }
      if (chat == null) {
        return;
      }

      final page = await api.appendMessage(
        character.avatar,
        chat.fileId,
        name: name?.trim().isNotEmpty == true ? name!.trim() : character.name,
        isUser: false,
        text: text.trim(),
      );
      messages = page.messages;
      loadedOffset = page.offset;
      loadedTotal = page.total;
      await loadChats();
      selectedChat = chats.firstWhere((item) => item.fileName == page.fileName,
          orElse: () => chat!);
    });
  }

  Future<void> deleteChat(ChatSummary chat) async {
    final character = selectedCharacter;
    if (character == null) {
      return;
    }

    await _run(() async {
      await api.deleteChat(character.avatar, chat.fileId);
      await loadChats(selectLast: true);
    });
  }

  Future<void> createBranchAt(int visibleMessageIndex, {int? swipeId}) async {
    final character = selectedCharacter;
    final chat = selectedChat;
    if (character == null || chat == null) {
      return;
    }

    await _run(() async {
      final page = await api.createBranch(
        character.avatar,
        chat.fileId,
        messageIndex: loadedOffset + visibleMessageIndex,
        swipeId: swipeId,
      );
      await loadChats();
      selectedChat = chats.firstWhere((item) => item.fileName == page.fileName,
          orElse: () => chat);
      messages = page.messages;
      loadedOffset = page.offset;
      loadedTotal = page.total;
    });
  }

  Future<void> selectSwipeAt(int visibleMessageIndex, int swipeId) async {
    final character = selectedCharacter;
    final chat = selectedChat;
    if (character == null || chat == null) {
      return;
    }

    await _run(() async {
      await api.selectSwipe(character.avatar, chat.fileId,
          loadedOffset + visibleMessageIndex, swipeId);
      await selectChat(chat);
    });
  }

  Future<void> saveCharacter(CharacterCard character) async {
    await _run(() async {
      final updated = await api.updateCharacter(character);
      selectedCharacter = updated;
      characters = characters
          .map((item) => item.avatar == updated.avatar ? updated : item)
          .toList();
    });
  }

  Future<void> updateProvider(ProviderSelection selection) async {
    await _run(() async {
      final catalog = providerCatalog;
      if (catalog == null) {
        return;
      }

      final normalized = _normalizeProviderSelection(selection, catalog);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        providerSelectionPrefsKey,
        jsonEncode(normalized.toJson(includeApiKey: false)),
      );
      final apiKey = normalized.apiKey.trim();
      if (apiKey.isEmpty) {
        await secureStorage.delete(key: providerApiKeySecureKey);
      } else {
        await secureStorage.write(key: providerApiKeySecureKey, value: apiKey);
      }
      providerCatalog = catalog.copyWith(current: normalized);
    });
  }

  Future<void> useServerPresetProvider() async {
    await _run(() async {
      final catalog = providerCatalog;
      if (catalog == null) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(providerSelectionPrefsKey);
      await secureStorage.delete(key: providerApiKeySecureKey);
      providerCatalog = catalog.copyWith(current: catalog.serverPreset);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (exception) {
      error = exception.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  ProviderCatalog _catalogWithLocalProvider(
      ProviderCatalog catalog, ProviderSelection? localSelection) {
    if (localSelection == null) {
      return catalog.copyWith(current: catalog.serverPreset);
    }
    return catalog.copyWith(
        current: _normalizeProviderSelection(localSelection, catalog));
  }

  Future<ProviderSelection?> _readLocalProviderSelection(
      SharedPreferences prefs) async {
    final raw = prefs.getString(providerSelectionPrefsKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(raw);
      final apiKey =
          await secureStorage.read(key: providerApiKeySecureKey) ?? '';
      if (json is Map<String, dynamic>) {
        return ProviderSelection.fromJson(json).copyWith(apiKey: apiKey);
      }
      if (json is Map) {
        return ProviderSelection.fromJson(Map<String, dynamic>.from(json))
            .copyWith(apiKey: apiKey);
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  ProviderSelection _normalizeProviderSelection(
      ProviderSelection selection, ProviderCatalog catalog) {
    final providerExists =
        catalog.providers.any((option) => option.id == selection.provider);
    final fallback = catalog.serverPreset;
    if (!providerExists) {
      return fallback;
    }

    final option = catalog.providers
        .firstWhere((provider) => provider.id == selection.provider);
    var source = selection.source;
    if (option.sources.isEmpty) {
      source = '';
    } else if (!option.sources.contains(source)) {
      source = option.sources.first;
    }

    return ProviderSelection(
      provider: selection.provider,
      source: source,
      model: selection.model,
      stream: selection.stream,
      modelKey: selection.modelKey,
      apiBaseUrl: selection.apiBaseUrl,
      apiKey: selection.apiKey,
      availableModels: selection.availableModels,
    );
  }

  String _providerSignature(ProviderSelection selection) {
    return jsonEncode({
      'provider': selection.provider,
      'source': selection.source,
      'model': selection.model,
      'stream': selection.stream,
      'apiBaseUrl': selection.apiBaseUrl,
      'apiKey': selection.apiKey,
    });
  }
}
