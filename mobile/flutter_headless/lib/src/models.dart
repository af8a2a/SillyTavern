class HeadlessBootstrap {
  const HeadlessBootstrap({
    required this.version,
    required this.userName,
    required this.remotePublicUrl,
  });

  factory HeadlessBootstrap.fromJson(Map<String, dynamic> json) {
    final user = asMap(json['user']);
    final remote = asMap(json['remoteApp']);
    return HeadlessBootstrap(
      version: stringOf(json['version'], fallback: 'v1'),
      userName: stringOf(user['name'], fallback: stringOf(user['handle'])),
      remotePublicUrl: stringOf(remote['publicUrl']),
    );
  }

  final String version;
  final String userName;
  final String remotePublicUrl;
}

class CharacterCard {
  const CharacterCard({
    required this.name,
    required this.avatar,
    required this.thumbnailUrl,
    required this.description,
    required this.personality,
    required this.scenario,
    required this.firstMessage,
    required this.messageExample,
    required this.creatorNotes,
    required this.tags,
    required this.raw,
  });

  factory CharacterCard.fromJson(Map<String, dynamic> json) {
    final data = asMap(json['data']);
    final headless = asMap(json['headless']);
    final extensions = asMap(data['extensions']);
    return CharacterCard(
      name: stringOf(json['name'],
          fallback: stringOf(data['name'], fallback: 'Unknown')),
      avatar: stringOf(json['avatar']),
      thumbnailUrl: stringOf(headless['thumbnail_url']),
      description: stringOf(json['description'],
          fallback: stringOf(data['description'])),
      personality: stringOf(json['personality'],
          fallback: stringOf(data['personality'])),
      scenario:
          stringOf(json['scenario'], fallback: stringOf(data['scenario'])),
      firstMessage: stringOf(
        json['first_mes'],
        fallback: stringOf(json['first_message'],
            fallback: stringOf(data['first_mes'])),
      ),
      messageExample: stringOf(json['mes_example'],
          fallback: stringOf(data['mes_example'])),
      creatorNotes: stringOf(
        json['creator_notes'],
        fallback: stringOf(extensions['creator_notes'],
            fallback: stringOf(data['creator_notes'])),
      ),
      tags: listOfStrings(json['tags']).isNotEmpty
          ? listOfStrings(json['tags'])
          : listOfStrings(data['tags']),
      raw: json,
    );
  }

  final String name;
  final String avatar;
  final String thumbnailUrl;
  final String description;
  final String personality;
  final String scenario;
  final String firstMessage;
  final String messageExample;
  final String creatorNotes;
  final List<String> tags;
  final Map<String, dynamic> raw;

  CharacterCard copyWith({
    String? name,
    String? description,
    String? personality,
    String? scenario,
    String? firstMessage,
    String? messageExample,
    String? creatorNotes,
    List<String>? tags,
  }) {
    return CharacterCard(
      name: name ?? this.name,
      avatar: avatar,
      thumbnailUrl: thumbnailUrl,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      scenario: scenario ?? this.scenario,
      firstMessage: firstMessage ?? this.firstMessage,
      messageExample: messageExample ?? this.messageExample,
      creatorNotes: creatorNotes ?? this.creatorNotes,
      tags: tags ?? this.tags,
      raw: raw,
    );
  }

  Map<String, dynamic> toPatch() {
    return {
      'name': name,
      'description': description,
      'personality': personality,
      'scenario': scenario,
      'first_mes': firstMessage,
      'mes_example': messageExample,
      'creator_notes': creatorNotes,
      'tags': tags,
      'data': {
        ...asMap(raw['data']),
        'name': name,
        'description': description,
        'personality': personality,
        'scenario': scenario,
        'first_mes': firstMessage,
        'mes_example': messageExample,
        'tags': tags,
        'extensions': {
          ...asMap(asMap(raw['data'])['extensions']),
          'creator_notes': creatorNotes,
        },
      },
    };
  }
}

class ChatSummary {
  const ChatSummary({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.fileSizeBytes,
    required this.chatItems,
    required this.preview,
    required this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      fileId: stringOf(json['file_id']),
      fileName: stringOf(json['file_name']),
      fileSize: stringOf(json['file_size']),
      fileSizeBytes: intOf(json['file_size_bytes']),
      chatItems: intOf(json['chat_items']),
      preview: stringOf(json['mes']),
      lastMessageAt: parseDate(json['last_mes']),
      createdAt: parseMillis(json['created_at']),
      updatedAt: parseMillis(json['updated_at']),
    );
  }

  final String fileId;
  final String fileName;
  final String fileSize;
  final int fileSizeBytes;
  final int chatItems;
  final String preview;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class ChatMessage {
  const ChatMessage({
    required this.name,
    required this.isUser,
    required this.text,
    required this.sendDate,
    required this.swipes,
    required this.swipeId,
    required this.branches,
    required this.raw,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final extra = asMap(json['extra']);
    return ChatMessage(
      name: stringOf(json['name'],
          fallback: json['is_user'] == true ? 'User' : 'Assistant'),
      isUser: json['is_user'] == true,
      text: stringOf(json['mes']),
      sendDate: parseDate(json['send_date']),
      swipes: listOfStrings(json['swipes']),
      swipeId: intOf(json['swipe_id']),
      branches: listOfStrings(extra['branches']),
      raw: json,
    );
  }

  final String name;
  final bool isUser;
  final String text;
  final DateTime? sendDate;
  final List<String> swipes;
  final int swipeId;
  final List<String> branches;
  final Map<String, dynamic> raw;

  bool get hasSwipes => swipes.length > 1;
}

class ChatPage {
  const ChatPage({
    required this.fileName,
    required this.fileId,
    required this.messages,
    required this.offset,
    required this.limit,
    required this.total,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
  });

  factory ChatPage.fromJson(Map<String, dynamic> json) {
    final pagination = asMap(json['pagination']);
    final rows = listOfMaps(json['messages']);
    final visibleRows =
        rows.where((row) => row['chat_metadata'] == null).toList();
    return ChatPage(
      fileName: stringOf(json['file_name']),
      fileId: stringOf(json['file_id']),
      messages: visibleRows.map(ChatMessage.fromJson).toList(),
      offset: intOf(pagination['offset']),
      limit: intOf(pagination['limit'], fallback: visibleRows.length),
      total: intOf(pagination['total'], fallback: visibleRows.length),
      hasMoreBefore: pagination['has_more_before'] == true,
      hasMoreAfter: pagination['has_more_after'] == true,
    );
  }

  final String fileName;
  final String fileId;
  final List<ChatMessage> messages;
  final int offset;
  final int limit;
  final int total;
  final bool hasMoreBefore;
  final bool hasMoreAfter;
}

class ProviderOption {
  const ProviderOption({
    required this.id,
    required this.label,
    required this.sources,
  });

  factory ProviderOption.fromJson(Map<String, dynamic> json) {
    return ProviderOption(
      id: stringOf(json['id']),
      label: stringOf(json['label'], fallback: stringOf(json['id'])),
      sources: listOfStrings(json['sources']),
    );
  }

  final String id;
  final String label;
  final List<String> sources;
}

class ProviderSelection {
  const ProviderSelection({
    required this.provider,
    required this.source,
    required this.model,
    required this.stream,
    required this.modelKey,
  });

  factory ProviderSelection.fromJson(Map<String, dynamic> json) {
    return ProviderSelection(
      provider: stringOf(json['provider']),
      source: stringOf(json['source']),
      model: stringOf(json['model']),
      stream: json['stream'] == true,
      modelKey: stringOf(json['modelKey']),
    );
  }

  final String provider;
  final String source;
  final String model;
  final bool stream;
  final String modelKey;
}

class ProviderCatalog {
  const ProviderCatalog({
    required this.current,
    required this.providers,
  });

  factory ProviderCatalog.fromJson(Map<String, dynamic> json) {
    return ProviderCatalog(
      current: ProviderSelection.fromJson(asMap(json['current'])),
      providers:
          listOfMaps(json['providers']).map(ProviderOption.fromJson).toList(),
    );
  }

  final ProviderSelection current;
  final List<ProviderOption> providers;
}

Map<String, dynamic> asMap(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

List<Map<String, dynamic>> listOfMaps(Object? value) {
  return value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];
}

List<String> listOfStrings(Object? value) {
  return value is List
      ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
      : <String>[];
}

String stringOf(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final result = value.toString();
  return result.isEmpty ? fallback : result;
}

int intOf(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? parseDate(Object? value) {
  if (value is num) {
    return parseMillis(value);
  }
  return DateTime.tryParse(value?.toString() ?? '');
}

DateTime? parseMillis(Object? value) {
  final millis =
      value is num ? value.round() : int.tryParse(value?.toString() ?? '');
  return millis == null || millis <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(millis);
}
