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

  void _handleBridgeMessage(String rawMessage) {
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
      result = _bridgeResult(method, args);
    } catch (exception) {
      ok = false;
      result = exception.toString();
    }

    if (id.isEmpty) {
      return;
    }

    controller.runJavaScript(
      'window.__SillyTavernMobileBridge&&'
      'window.__SillyTavernMobileBridge.resolve('
      '${jsonEncode(id)},$ok,${jsonEncode(result)});',
    );
  }

  Object? _bridgeResult(String method, List<Object?> args) {
    switch (method) {
      case 'getChatMessages':
        return _bridgeMessages(widget.state);
      case 'getChatMessage':
        final messageIndex = _intFromObject(args.isEmpty ? null : args.first);
        return _bridgeMessage(widget.state, messageIndex);
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
        return null;
      case 'triggerSlashWithResult':
        return null;
      default:
        throw UnsupportedError('Unsupported mobile bridge method: $method');
    }
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

List<Map<String, dynamic>> _bridgeMessages(AppState state) {
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
