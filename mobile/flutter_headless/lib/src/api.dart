import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class HeadlessApiException implements Exception {
  const HeadlessApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HeadlessApi {
  HeadlessApi(String baseUrl) : _baseUrl = _normalizeBaseUrl(baseUrl);

  String _baseUrl;
  String? _csrfToken;
  final Map<String, String> _cookies = <String, String>{};

  String get baseUrl => _baseUrl;

  set baseUrl(String value) {
    _baseUrl = _normalizeBaseUrl(value);
    _csrfToken = null;
    _cookies.clear();
  }

  String get cookieHeader =>
      _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  Map<String, String> get imageHeaders =>
      cookieHeader.isEmpty ? <String, String>{} : {'cookie': cookieHeader};

  Uri uri(String path,
      [Map<String, String?> query = const <String, String?>{}]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final url = Uri.parse('$_baseUrl$normalizedPath');
    final queryParameters = <String, String>{
      ...url.queryParameters,
      for (final entry in query.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    return url.replace(
        queryParameters: queryParameters.isEmpty ? null : queryParameters);
  }

  String mediaUrl(String path) => uri(path).toString();

  Future<HeadlessBootstrap> bootstrap() async {
    final json = await getJson('/api/headless/v1/bootstrap');
    return HeadlessBootstrap.fromJson(json);
  }

  Future<List<CharacterCard>> characters({bool full = false}) async {
    final json = await getJson(
        '/api/headless/v1/characters', {'full': full ? 'true' : null});
    return listOfMaps(json['items']).map(CharacterCard.fromJson).toList();
  }

  Future<CharacterCard> character(String avatar) async {
    final json = await getJson(
        '/api/headless/v1/characters/${Uri.encodeComponent(avatar)}');
    return CharacterCard.fromJson(asMap(json['character']));
  }

  Future<CharacterCard> updateCharacter(CharacterCard character) async {
    final json = await patchJson(
      '/api/headless/v1/characters/${Uri.encodeComponent(character.avatar)}',
      character.toPatch(),
    );
    return CharacterCard.fromJson(asMap(json['character']));
  }

  Future<List<ChatSummary>> chats(String avatar,
      {String sort = 'date', bool ascending = false}) async {
    final json = await getJson(
      '/api/headless/v1/characters/${Uri.encodeComponent(avatar)}/chats',
      {
        'sort': sort,
        'direction': ascending ? 'asc' : 'desc',
      },
    );
    return listOfMaps(json['items']).map(ChatSummary.fromJson).toList();
  }

  Future<ChatPage> chatPage(
    String avatar,
    String chatId, {
    required int offset,
    required int limit,
  }) async {
    final json = await getJson(
      '/api/headless/v1/characters/${Uri.encodeComponent(avatar)}/chats/${Uri.encodeComponent(chatId)}',
      {
        'offset': '$offset',
        'limit': '$limit',
      },
    );
    return ChatPage.fromJson(json);
  }

  Future<ChatPage> createChat(String avatar, {String? name}) async {
    final json = await postJson(
      '/api/headless/v1/characters/${Uri.encodeComponent(avatar)}/chats',
      {
        if (name != null && name.trim().isNotEmpty) 'id': name.trim(),
        'messages': <Map<String, dynamic>>[],
      },
    );
    return ChatPage.fromJson({
      ...json,
      'pagination': {
        'offset': 0,
        'limit': 0,
        'total': 0,
        'has_more_before': false,
        'has_more_after': false,
      },
    });
  }

  Future<ChatPage> appendMessage(
    String avatar,
    String chatId, {
    required String name,
    required bool isUser,
    required String text,
  }) async {
    final json = await postJson(
      '/api/headless/v1/characters/${Uri.encodeComponent(avatar)}/chats/${Uri.encodeComponent(chatId)}/messages',
      {
        'name': name,
        'is_user': isUser,
        'mes': text,
        'send_date': DateTime.now().toIso8601String(),
      },
    );
    final rows = listOfMaps(json['messages']);
    return ChatPage.fromJson({
      ...json,
      'messages': rows,
      'pagination': {
        'offset': 0,
        'limit': rows.length,
        'total': rows.where((row) => row['chat_metadata'] == null).length,
        'has_more_before': false,
        'has_more_after': false,
      },
    });
  }

  Future<ChatPage> createBranch(
    String avatar,
    String chatId, {
    required int messageIndex,
    int? swipeId,
  }) async {
    final json = await postJson(
      '/api/headless/v1/characters/${Uri.encodeComponent(avatar)}/chats/${Uri.encodeComponent(chatId)}/branches',
      {
        'message_index': messageIndex,
        if (swipeId != null) 'swipe_id': swipeId,
      },
    );
    final rows = listOfMaps(json['messages']);
    return ChatPage.fromJson({
      ...json,
      'messages': rows,
      'pagination': {
        'offset': 0,
        'limit': rows.length,
        'total': rows.where((row) => row['chat_metadata'] == null).length,
        'has_more_before': false,
        'has_more_after': false,
      },
    });
  }

  Future<void> selectSwipe(
      String avatar, String chatId, int messageIndex, int swipeId) async {
    await patchJson(
      '/api/headless/v1/characters/${Uri.encodeComponent(avatar)}/chats/${Uri.encodeComponent(chatId)}/messages/$messageIndex/swipe',
      {'swipe_id': swipeId},
    );
  }

  Future<void> deleteChat(String avatar, String chatId) async {
    await deleteJson(
        '/api/headless/v1/characters/${Uri.encodeComponent(avatar)}/chats/${Uri.encodeComponent(chatId)}');
  }

  Future<ProviderCatalog> providers() async {
    final json = await getJson('/api/headless/v1/providers');
    return ProviderCatalog.fromJson(json);
  }

  Future<Map<String, dynamic>> getJson(String path,
      [Map<String, String?> query = const <String, String?>{}]) async {
    final response = await http.get(uri(path, query), headers: _headers());
    return _decode(response);
  }

  Future<Map<String, dynamic>> postJson(
      String path, Map<String, dynamic> body) async {
    await _ensureCsrf();
    final response = await http.post(uri(path),
        headers: _headers(mutating: true), body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> patchJson(
      String path, Map<String, dynamic> body) async {
    await _ensureCsrf();
    final response = await http.patch(uri(path),
        headers: _headers(mutating: true), body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    await _ensureCsrf();
    final response =
        await http.delete(uri(path), headers: _headers(mutating: true));
    return _decode(response);
  }

  Future<void> _ensureCsrf() async {
    if (_csrfToken != null) {
      return;
    }
    final json = await getJson('/csrf-token');
    _csrfToken = stringOf(json['token']);
  }

  Map<String, String> _headers({bool mutating = false}) {
    return {
      'accept': 'application/json',
      if (mutating) 'content-type': 'application/json',
      if (mutating && _csrfToken != null) 'x-csrf-token': _csrfToken!,
      if (cookieHeader.isNotEmpty) 'cookie': cookieHeader,
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    _storeCookies(response);
    final text = utf8.decode(response.bodyBytes);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HeadlessApiException(
          text.isEmpty ? 'HTTP ${response.statusCode}' : text);
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const HeadlessApiException('Unexpected API response');
    }

    return Map<String, dynamic>.from(decoded);
  }

  void _storeCookies(http.Response response) {
    final rawCookie = response.headers['set-cookie'];
    if (rawCookie == null || rawCookie.isEmpty) {
      return;
    }

    for (final cookie in rawCookie.split(RegExp(',(?=[^;]+=)'))) {
      final pair = cookie.split(';').first.split('=');
      if (pair.length >= 2 && pair.first.trim().isNotEmpty) {
        _cookies[pair.first.trim()] = pair.sublist(1).join('=').trim();
      }
    }
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed =
        value.trim().isEmpty ? 'http://127.0.0.1:8000' : value.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

class OpenAiCompatibleApi {
  const OpenAiCompatibleApi._();

  static Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final response = await http
        .get(
          _uri(baseUrl, '/models'),
          headers: _headers(apiKey),
        )
        .timeout(const Duration(seconds: 20));
    final json = _decodeExternal(response);
    final models = listOfMaps(json['data'])
        .map((item) => stringOf(item['id']))
        .where((id) => id.isNotEmpty)
        .toList()
      ..sort();

    if (models.isEmpty) {
      throw const HeadlessApiException('没有从 /models 获取到可用模型');
    }

    return models;
  }

  static Future<String> testConnection({
    required String baseUrl,
    required String apiKey,
  }) async {
    final models = await fetchModels(baseUrl: baseUrl, apiKey: apiKey);
    return '连接成功，获取到 ${models.length} 个模型';
  }

  static Future<String> sendTestMessage({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    if (model.trim().isEmpty) {
      throw const HeadlessApiException('请先选择或输入模型名');
    }

    final response = await http
        .post(
          _uri(baseUrl, '/chat/completions'),
          headers: {
            ..._headers(apiKey),
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': model.trim(),
            'messages': [
              {'role': 'user', 'content': 'Reply with OK.'},
            ],
            'max_tokens': 8,
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final json = _decodeExternal(response);
    final choices = listOfMaps(json['choices']);
    final first = choices.isEmpty ? <String, dynamic>{} : choices.first;
    final message = asMap(first['message']);
    final content = stringOf(message['content'],
        fallback: stringOf(first['text'], fallback: '测试消息发送成功'));
    return content.trim().isEmpty ? '测试消息发送成功' : content.trim();
  }

  static Uri _uri(String baseUrl, String suffix) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw const HeadlessApiException('请先填写自定义端点');
    }

    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final parsed = Uri.parse(withScheme);
    var path = parsed.path.replaceAll(RegExp(r'/+$'), '');

    if (path.endsWith('/chat/completions')) {
      path = path.substring(0, path.length - '/chat/completions'.length);
    }
    if (path.endsWith('/models')) {
      path = path.substring(0, path.length - '/models'.length);
    }
    if (path.isEmpty) {
      path = '/v1';
    }

    final nextPath = '$path$suffix'.replaceAll(RegExp(r'//+'), '/');
    return parsed.replace(path: nextPath, queryParameters: null);
  }

  static Map<String, String> _headers(String apiKey) {
    return {
      'accept': 'application/json',
      if (apiKey.trim().isNotEmpty) 'authorization': 'Bearer ${apiKey.trim()}',
    };
  }

  static Map<String, dynamic> _decodeExternal(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    final json = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = asMap(json['error']);
      throw HeadlessApiException(
        stringOf(error['message'],
            fallback:
                '请求失败：HTTP ${response.statusCode}${text.isEmpty ? '' : ' $text'}'),
      );
    }

    if (decoded is! Map) {
      throw const HeadlessApiException('Unexpected API response');
    }

    return json;
  }
}
