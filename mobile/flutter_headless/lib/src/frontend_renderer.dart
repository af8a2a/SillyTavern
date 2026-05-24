import 'dart:convert';

import 'models.dart';

class FrontendHtmlBlock {
  const FrontendHtmlBlock({
    required this.html,
    required this.remainingText,
  });

  final String html;
  final String remainingText;
}

final RegExp _htmlFencePattern = RegExp(
  r'```[ \t]*html[^\r\n]*\r?\n([\s\S]*?)```',
  caseSensitive: false,
);
final RegExp _bodyOpenPattern = RegExp(
  r'<body(?:\s|>)',
  caseSensitive: false,
);
final RegExp _bodyClosePattern = RegExp(
  r'</body\s*>',
  caseSensitive: false,
);
final RegExp _headClosePattern = RegExp(
  r'</head\s*>',
  caseSensitive: false,
);
final RegExp _bodyCloseInsertPattern = RegExp(
  r'</body\s*>',
  caseSensitive: false,
);
final RegExp _htmlOpenPattern = RegExp(
  r'<html(?:\s|>)',
  caseSensitive: false,
);
final RegExp _viewportPattern = RegExp(
  '<meta\\s+name=["\\\']viewport["\\\']',
  caseSensitive: false,
);
final RegExp _basePattern = RegExp(
  r'<base(?:\s|>)',
  caseSensitive: false,
);
const String _hostStyle = '''
<style id="st-mobile-host-style">
  html,
  body {
    max-width: 100%;
    min-height: 100%;
    overflow-x: hidden !important;
    overflow-y: auto !important;
    -webkit-overflow-scrolling: touch;
    overscroll-behavior: contain;
    overflow-wrap: anywhere;
  }

  body {
    margin: 0;
  }

  ::-webkit-scrollbar {
    width: 7px;
    height: 7px;
  }

  ::-webkit-scrollbar-track {
    background: rgba(255, 255, 255, .08);
  }

  ::-webkit-scrollbar-thumb {
    background: rgba(0, 170, 190, .55);
    border-radius: 999px;
  }
</style>''';

String applyCharacterDisplayRegexes(String text, CharacterCard character) {
  var result = text;
  final data = asMap(character.raw['data']);
  final rawScripts = [
    ...listOfMaps(asMap(character.raw['extensions'])['regex_scripts']),
    ...listOfMaps(asMap(data['extensions'])['regex_scripts']),
  ];

  for (final script in rawScripts) {
    if (script['disabled'] == true || script['promptOnly'] == true) {
      continue;
    }

    final findRegex = stringOf(script['findRegex']);
    final replaceString = stringOf(script['replaceString']);
    if (findRegex.isEmpty) {
      continue;
    }

    try {
      result = result.replaceAllMapped(
        RegExp(findRegex, multiLine: true),
        (_) => replaceString,
      );
    } catch (_) {
      continue;
    }
  }

  return result;
}

FrontendHtmlBlock? extractFrontendHtmlBlock(String text) {
  for (final match in _htmlFencePattern.allMatches(text)) {
    final html = (match.group(1) ?? '').trim();
    if (!isRenderableFrontendHtml(html)) {
      continue;
    }

    final before = text.substring(0, match.start).trim();
    final after = text.substring(match.end).trim();
    return FrontendHtmlBlock(
      html: html,
      remainingText:
          [before, after].where((part) => part.isNotEmpty).join('\n\n').trim(),
    );
  }

  final trimmed = text.trim();
  if (_htmlOpenPattern.hasMatch(trimmed) && isRenderableFrontendHtml(trimmed)) {
    return FrontendHtmlBlock(html: trimmed, remainingText: '');
  }

  return null;
}

bool isRenderableFrontendHtml(String html) {
  return _bodyOpenPattern.hasMatch(html) && _bodyClosePattern.hasMatch(html);
}

String buildFrontendDocument({
  required String html,
  required Map<String, dynamic> context,
  String? baseHref,
}) {
  final document = _ensureDocument(html.trim());
  final charAvatarUrl = _stringFromPath(context, ['character', 'avatarUrl']);
  final userAvatarUrl = _stringFromPath(context, ['user', 'avatarUrl']);
  final withMacros = _replaceAvatarMacros(
    document,
    charAvatarUrl: charAvatarUrl,
    userAvatarUrl: userAvatarUrl,
  );

  final mobileContext = jsonEncode(context);
  final headInjection = [
    if (!_viewportPattern.hasMatch(withMacros))
      '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
    if (baseHref != null &&
        baseHref.trim().isNotEmpty &&
        !_basePattern.hasMatch(withMacros))
      '<base href="${_escapeHtmlAttribute(_baseWithTrailingSlash(baseHref))}">',
    _hostStyle,
    _buildHeadScript(mobileContext),
  ].join('\n');

  final bodyInjection = _buildBodyScript(
    charAvatarUrl: charAvatarUrl,
    userAvatarUrl: userAvatarUrl,
  );

  return _insertBefore(
    _insertBefore(withMacros, _headClosePattern, '$headInjection\n'),
    _bodyCloseInsertPattern,
    '$bodyInjection\n',
  );
}

String _ensureDocument(String html) {
  if (_htmlOpenPattern.hasMatch(html)) {
    return html;
  }

  return '<!doctype html><html><head><meta charset="utf-8"></head><body>$html</body></html>';
}

String _replaceAvatarMacros(
  String html, {
  required String charAvatarUrl,
  required String userAvatarUrl,
}) {
  return html
      .replaceAll('{{charAvatarPath}}', charAvatarUrl)
      .replaceAll('{{userAvatarPath}}', userAvatarUrl);
}

String _buildHeadScript(String mobileContext) {
  return '''
<script>
(function () {
  window.SillyTavernMobile = $mobileContext;
  window.TavernHelper = window.TavernHelper || {};
  window.TavernHelper.mobile = window.SillyTavernMobile;

  const pending = new Map();
  let nextRequestId = 1;

  function bridgeRequest(method, args) {
    if (!window.MobileTavernBridge || !window.MobileTavernBridge.postMessage) {
      return Promise.reject(new Error('Mobile bridge unavailable'));
    }
    const id = String(nextRequestId++);
    const payload = { id, method, args: Array.isArray(args) ? args : [] };
    return new Promise(function (resolve, reject) {
      pending.set(id, { resolve, reject });
      window.MobileTavernBridge.postMessage(JSON.stringify(payload));
    });
  }

  window.__SillyTavernMobileBridge = {
    request: bridgeRequest,
    resolve: function (id, ok, value) {
      const callbacks = pending.get(String(id));
      if (!callbacks) return;
      pending.delete(String(id));
      if (ok) callbacks.resolve(value);
      else callbacks.reject(new Error(String(value || 'Mobile bridge error')));
    },
  };

  window.TavernHelper.mobile.request = bridgeRequest;
  window.getContext = window.getContext || function () {
    return Promise.resolve(window.SillyTavernMobile);
  };
  window.getChatMessages = window.getChatMessages || function () {
    return bridgeRequest('getChatMessages', Array.prototype.slice.call(arguments));
  };
  window.getChatMessage = window.getChatMessage || function (messageId) {
    return bridgeRequest('getChatMessage', [messageId]);
  };
  window.setChatMessage = window.setChatMessage || function (message, messageId, options) {
    return bridgeRequest('setChatMessage', [message, messageId, options || {}]);
  };
  window.getCurrentMessageId = window.getCurrentMessageId || function () {
    return bridgeRequest('getCurrentMessageId');
  };
  window.getLastMessageId = window.getLastMessageId || function () {
    return bridgeRequest('getLastMessageId');
  };
  window.replaceVariables = window.replaceVariables || function (value) {
    return bridgeRequest('replaceVariables', [value]);
  };
  window.triggerSlash = window.triggerSlash || function (command) {
    return bridgeRequest('triggerSlash', [command]);
  };
  window.triggerSlashWithResult = window.triggerSlashWithResult || function (command) {
    return bridgeRequest('triggerSlashWithResult', [command]);
  };
  window.SillyTavern = window.SillyTavern || {};
  window.SillyTavern.getContext = window.SillyTavern.getContext || function () {
    return window.SillyTavernMobile;
  };
  window.SillyTavern.executeSlashCommandsWithOptions =
    window.SillyTavern.executeSlashCommandsWithOptions ||
    function (command) {
      return bridgeRequest('triggerSlashWithResult', [command]);
    };
})();
</script>''';
}

String _buildBodyScript({
  required String charAvatarUrl,
  required String userAvatarUrl,
}) {
  final charAvatar = jsonEncode(charAvatarUrl);
  final userAvatar = jsonEncode(userAvatarUrl);
  return '''
<script>
(function () {
  const charAvatarUrl = $charAvatar;
  const userAvatarUrl = $userAvatar;
  function setAvatar(selector, url) {
    if (!url) return;
    document.querySelectorAll(selector).forEach(function (element) {
      element.style.backgroundImage = 'url("' + url.replace(/"/g, '%22') + '")';
    });
  }
  function applyAvatars() {
    setAvatar('.char-avatar, .char_avatar', charAvatarUrl);
    setAvatar('.user-avatar, .user_avatar', userAvatarUrl);
  }
  function postHeight() {
    const root = document.documentElement;
    const body = document.body;
    const height = Math.ceil(Math.max(
      root ? root.scrollHeight : 0,
      body ? body.scrollHeight : 0,
      window.innerHeight || 0
    ));
    if (window.TavernFrontendHeight && window.TavernFrontendHeight.postMessage) {
      window.TavernFrontendHeight.postMessage(String(height));
    }
  }
  function sync() {
    applyAvatars();
    postHeight();
  }
  window.addEventListener('load', function () {
    setTimeout(sync, 40);
    setTimeout(sync, 300);
    setTimeout(sync, 1000);
  });
  if (window.ResizeObserver) {
    new ResizeObserver(sync).observe(document.documentElement);
  }
  sync();
})();
</script>''';
}

String _insertBefore(String html, RegExp pattern, String insertion) {
  final match = pattern.firstMatch(html);
  if (match == null) {
    return '$html\n$insertion';
  }
  return '${html.substring(0, match.start)}$insertion${html.substring(match.start)}';
}

String _stringFromPath(Map<String, dynamic> map, List<String> path) {
  dynamic current = map;
  for (final segment in path) {
    if (current is! Map) {
      return '';
    }
    current = current[segment];
  }
  return current?.toString() ?? '';
}

String _escapeHtmlAttribute(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _baseWithTrailingSlash(String value) {
  return value.endsWith('/') ? value : '$value/';
}
