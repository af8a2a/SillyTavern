import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sillytavern_headless/main.dart';
import 'package:sillytavern_headless/src/app_state.dart';
import 'package:sillytavern_headless/src/frontend_renderer.dart';
import 'package:sillytavern_headless/src/models.dart';

void main() {
  test('extracts renderable fenced HTML frontend blocks', () {
    final block = extractFrontendHtmlBlock('intro\n```html\n'
        '<html><body><div class="char_avatar">{{charAvatarPath}}</div></body></html>'
        '\n```\noutro');

    expect(block, isNotNull);
    expect(block!.html, contains('<body>'));
    expect(block.remainingText, 'intro\n\noutro');
  });

  test('ignores HTML fences without a body element', () {
    final block =
        extractFrontendHtmlBlock('```html\n<div>plain status</div>\n```');

    expect(block, isNull);
  });

  test('injects mobile context and avatar compatibility helpers', () {
    final document = buildFrontendDocument(
      html: '<html><head></head><body>'
          '<div class="user-avatar">{{userAvatarPath}}</div>'
          '<div class="char-avatar">{{charAvatarPath}}</div>'
          '</body></html>',
      baseHref: 'http://127.0.0.1:8000',
      context: const {
        'character': {'avatarUrl': 'http://127.0.0.1:8000/char.png'},
        'user': {'avatarUrl': 'http://127.0.0.1:8000/user.png'},
      },
    );

    expect(document, contains('window.SillyTavernMobile'));
    expect(document, contains('http://127.0.0.1:8000/char.png'));
    expect(document, contains('http://127.0.0.1:8000/user.png'));
    expect(document, contains('TavernFrontendHeight.postMessage'));
    expect(document, contains('overflow-y: auto'));
    expect(document, contains('::-webkit-scrollbar'));
  });

  testWidgets('renders the mobile navigation destinations', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('聊天'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('provider sheet exposes OpenAI compatible configuration',
      (tester) async {
    final state = AppState();
    addTearDown(state.dispose);

    state.providerCatalog = const ProviderCatalog(
      current: ProviderSelection(
        provider: 'openai',
        source: 'custom',
        model: 'gpt-4o',
        stream: true,
        modelKey: 'custom_model',
        apiBaseUrl: 'http://localhost:1234/v1',
        apiKey: 'test-key',
        availableModels: ['gpt-4o'],
      ),
      serverPreset: ProviderSelection(
        provider: 'openai',
        source: 'custom',
        model: 'gpt-4o',
        stream: true,
        modelKey: 'custom_model',
        apiBaseUrl: '',
        apiKey: '',
        availableModels: [],
      ),
      providers: [
        ProviderOption(
          id: 'openai',
          label: 'Chat Completion',
          sources: ['custom'],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showProviderSheet(context, state),
              child: const Text('open provider sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open provider sheet'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI 兼容参数'), findsOneWidget);
    expect(find.text('使用服务端模型提供商'), findsOneWidget);
    expect(find.text('自定义端点（基础 URL）'), findsOneWidget);
    expect(find.text('自定义 API 密钥（可选）'), findsOneWidget);
    expect(find.text('可用模型'), findsOneWidget);
    expect(find.text('连接测试'), findsOneWidget);
    expect(find.text('获取模型'), findsOneWidget);
    expect(find.text('发送测试消息'), findsOneWidget);
  });
}
