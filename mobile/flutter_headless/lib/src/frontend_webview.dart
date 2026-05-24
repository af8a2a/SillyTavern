import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api.dart';
import 'app_state.dart';
import 'frontend_renderer.dart';
import 'models.dart';

class FrontendHtmlView extends StatefulWidget {
  const FrontendHtmlView({
    required this.state,
    required this.character,
    required this.html,
    this.messageIndex,
    this.isStarter = false,
    super.key,
  });

  final AppState state;
  final CharacterCard character;
  final String html;
  final int? messageIndex;
  final bool isStarter;

  @override
  State<FrontendHtmlView> createState() => _FrontendHtmlViewState();
}

class _FrontendHtmlViewState extends State<FrontendHtmlView> {
  late final WebViewController controller;
  double contentHeight = 520;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'TavernFrontendHeight',
        onMessageReceived: (message) {
          final nextHeight = double.tryParse(message.message);
          if (nextHeight == null || !mounted) {
            return;
          }
          setState(() {
            contentHeight = nextHeight.clamp(220, 1200).toDouble();
          });
        },
      )
      ..addJavaScriptChannel(
        'MobileTavernBridge',
        onMessageReceived: (message) {
          _handleBridgeMessage(message.message);
        },
      );
    _loadDocument();
  }

  @override
  void didUpdateWidget(covariant FrontendHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.character.avatar != widget.character.avatar ||
        oldWidget.state.bootstrap?.userAvatar !=
            widget.state.bootstrap?.userAvatar ||
        oldWidget.state.currentProvider?.model !=
            widget.state.currentProvider?.model) {
      _loadDocument();
    }
  }

  void _loadDocument() {
    final document = buildFrontendDocument(
      html: widget.html,
      baseHref: widget.state.api.baseUrl,
      context: _frontendContext(
        state: widget.state,
        character: widget.character,
        messageIndex: widget.messageIndex,
        isStarter: widget.isStarter,
      ),
    );
    controller.loadHtmlString(
      document,
      baseUrl: _baseWithTrailingSlash(widget.state.api.baseUrl),
    );
  }

  Future<void> _handleBridgeMessage(String rawMessage) async {
    String id = '';
    Object? result;
    var ok = true;

    try {
      final payload = jsonDecode(rawMessage);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid bridge payload');
      }
      id = payload['id']?.toString() ?? '';
      final method = payload['method']?.toString() ?? '';
      final args = payload['args'] is List
          ? List<Object?>.from(payload['args'])
          : <Object?>[];
      result = await _bridgeResult(method, args);
    } catch (exception) {
      ok = false;
      result = exception.toString();
    }

    if (id.isEmpty) {
      return;
    }

    try {
      await controller.runJavaScript(
        'window.__SillyTavernMobileBridge&&'
        'window.__SillyTavernMobileBridge.resolve('
        '${jsonEncode(id)},$ok,${jsonEncode(result)});',
      );
    } catch (_) {
      // The source WebView may have been rebuilt by a bridge-triggered state update.
    }
  }

  Future<Object?> _bridgeResult(String method, List<Object?> args) async {
    switch (method) {
      case 'getChatMessages':
        return _bridgeMessages(
          widget.state,
          character: widget.character,
          isStarter: widget.isStarter,
        );
      case 'getChatMessage':
        final messageIndex = _intFromObject(args.isEmpty ? null : args.first);
        return _bridgeMessage(widget.state, messageIndex);
      case 'setChatMessage':
        return _setChatMessage(args);
      case 'getCurrentMessageId':
        return widget.messageIndex;
      case 'getLastMessageId':
        return _lastLoadedMessageIndex(widget.state);
      case 'replaceVariables':
        return _replaceMobileVariables(
          args.isEmpty ? '' : args.first?.toString() ?? '',
          state: widget.state,
          character: widget.character,
        );
      case 'triggerSlash':
        return _triggerSlash(args, expectResult: false);
      case 'triggerSlashWithResult':
        return _triggerSlash(args, expectResult: true);
      default:
        throw UnsupportedError('Unsupported mobile bridge method: $method');
    }
  }

  Future<bool> _setChatMessage(List<Object?> args) async {
    final messageIndex =
        _intFromObject(args.length > 1 ? args[1] : null) ?? widget.messageIndex;
    if (messageIndex == null) {
      return false;
    }

    final options = args.length > 2 && args[2] is Map
        ? Map<Object?, Object?>.from(args[2] as Map)
        : <Object?, Object?>{};
    final swipeId = _intFromObject(
      options['swipe_id'] ?? options['swipeId'] ?? options['swipe'],
    );
    if (swipeId == null) {
      return false;
    }

    final visibleIndex = _visibleMessageIndex(widget.state, messageIndex);
    if (visibleIndex == null) {
      if (!widget.isStarter) {
        return false;
      }

      final text = _starterSwipeText(
        widget.character,
        swipeId,
        args.isEmpty ? null : args.first,
      );
      if (text.trim().isEmpty) {
        return false;
      }

      await widget.state.startChatWithAssistantMessage(
        text,
        name: widget.character.name,
      );
      return true;
    }

    await widget.state.selectSwipeAt(visibleIndex, swipeId);
    return true;
  }

  Future<Object?> _triggerSlash(List<Object?> args,
      {required bool expectResult}) async {
    final command = args.isEmpty ? '' : args.first?.toString().trim() ?? '';
    final sendMatch = RegExp(r'^/send\s+([\s\S]+)$', caseSensitive: false)
        .firstMatch(command);
    if (sendMatch != null) {
      final text = sendMatch.group(1)?.trim() ?? '';
      if (text.isNotEmpty) {
        await widget.state.sendUserMessage(text);
      }
      return expectResult ? text : null;
    }

    return expectResult ? '' : null;
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    final viewHeight = contentHeight.clamp(220, maxHeight).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffd9dde2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: viewHeight,
          width: double.infinity,
          child: WebViewWidget(
            controller: controller,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
              Factory<LongPressGestureRecognizer>(
                LongPressGestureRecognizer.new,
              ),
              Factory<VerticalDragGestureRecognizer>(
                VerticalDragGestureRecognizer.new,
              ),
            },
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _frontendContext({
  required AppState state,
  required CharacterCard character,
  required int? messageIndex,
  required bool isStarter,
}) {
  final provider = state.currentProvider;
  return {
    'platform': 'flutter_headless',
    'api': {
      'baseUrl': state.api.baseUrl,
    },
    'character': {
      'name': character.name,
      'avatar': character.avatar,
      'avatarUrl': _characterAvatarUrl(state, character),
    },
    'user': {
      'name': state.bootstrap?.userName ?? 'User',
      'avatar': state.bootstrap?.userAvatar ?? '',
      'avatarUrl': _userAvatarUrl(state),
    },
    'provider': provider?.toJson(includeApiKey: false),
    'chat': {
      'id': state.selectedChat?.fileId,
      'fileName': state.selectedChat?.fileName,
      'messageCount':
          state.loadedTotal > 0 ? state.loadedTotal : state.messages.length,
    },
    'message': {
      'index': messageIndex,
      'isStarter': isStarter,
    },
  };
}

List<Map<String, dynamic>> _bridgeMessages(
  AppState state, {
  required CharacterCard character,
  required bool isStarter,
}) {
  if (state.messages.isEmpty && isStarter) {
    return [
      {
        'id': 0,
        'name': character.name,
        'is_user': false,
        'mes': character.firstMessage,
        'send_date': null,
        'swipes': [
          character.firstMessage,
          ...character.alternateGreetings,
        ],
        'swipe_id': 0,
      },
    ];
  }

  return [
    for (var i = 0; i < state.messages.length; i++)
      _bridgeMessageJson(state.messages[i], state.loadedOffset + i),
  ];
}

Map<String, dynamic>? _bridgeMessage(AppState state, int? messageIndex) {
  if (messageIndex == null) {
    return null;
  }
  final localIndex = messageIndex - state.loadedOffset;
  if (localIndex >= 0 && localIndex < state.messages.length) {
    return _bridgeMessageJson(state.messages[localIndex], messageIndex);
  }
  if (messageIndex >= 0 && messageIndex < state.messages.length) {
    return _bridgeMessageJson(
      state.messages[messageIndex],
      state.loadedOffset + messageIndex,
    );
  }
  return null;
}

int? _visibleMessageIndex(AppState state, int messageIndex) {
  final localIndex = messageIndex - state.loadedOffset;
  if (localIndex >= 0 && localIndex < state.messages.length) {
    return localIndex;
  }
  if (messageIndex >= 0 && messageIndex < state.messages.length) {
    return messageIndex;
  }
  return null;
}

String _starterSwipeText(
  CharacterCard character,
  int swipeId,
  Object? requestedText,
) {
  if (swipeId == 0) {
    return character.firstMessage;
  }
  final alternateIndex = swipeId - 1;
  if (alternateIndex >= 0 &&
      alternateIndex < character.alternateGreetings.length) {
    return character.alternateGreetings[alternateIndex];
  }
  return requestedText?.toString() ?? '';
}

Map<String, dynamic> _bridgeMessageJson(ChatMessage message, int messageIndex) {
  return {
    'id': messageIndex,
    'name': message.name,
    'is_user': message.isUser,
    'mes': message.text,
    'send_date': message.sendDate?.toIso8601String(),
    'swipes': message.swipes,
    'swipe_id': message.swipeId,
  };
}

int? _lastLoadedMessageIndex(AppState state) {
  if (state.messages.isEmpty) {
    return null;
  }
  return state.loadedOffset + state.messages.length - 1;
}

String _replaceMobileVariables(
  String value, {
  required AppState state,
  required CharacterCard character,
}) {
  return value
      .replaceAll('{{char}}', character.name)
      .replaceAll('{{user}}', state.bootstrap?.userName ?? 'User')
      .replaceAll('{{charAvatarPath}}', _characterAvatarUrl(state, character))
      .replaceAll('{{userAvatarPath}}', _userAvatarUrl(state));
}

int? _intFromObject(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

String _characterAvatarUrl(AppState state, CharacterCard character) {
  if (character.thumbnailUrl.trim().isNotEmpty) {
    return _absoluteHeadlessUrl(state.api, character.thumbnailUrl);
  }
  if (character.avatar.trim().isEmpty) {
    return '';
  }
  return _absoluteHeadlessUrl(
    state.api,
    '/characters/${Uri.encodeComponent(character.avatar)}',
  );
}

String _userAvatarUrl(AppState state) {
  final avatar = state.bootstrap?.userAvatar.trim() ?? '';
  if (avatar.isEmpty) {
    return '';
  }
  return state.api.uri('/thumbnail', {
    'type': 'persona',
    'file': avatar,
  }).toString();
}

String _absoluteHeadlessUrl(HeadlessApi api, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    return trimmed;
  }
  return api.uri(trimmed).toString();
}

String _baseWithTrailingSlash(String value) {
  return value.endsWith('/') ? value : '$value/';
}
