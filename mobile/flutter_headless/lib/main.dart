import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'src/app_state.dart';
import 'src/models.dart';

void main() {
  runApp(const SillyTavernHeadlessApp());
}

class SillyTavernHeadlessApp extends StatelessWidget {
  const SillyTavernHeadlessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SillyTavern Headless',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2f6f82)),
        scaffoldBackgroundColor: const Color(0xfff7f7f9),
        fontFamilyFallback: const ['PingFang SC', 'Noto Sans CJK SC', 'Roboto'],
      ),
      home: const HeadlessHomePage(),
    );
  }
}

class HeadlessHomePage extends StatefulWidget {
  const HeadlessHomePage({super.key});

  @override
  State<HeadlessHomePage> createState() => _HeadlessHomePageState();
}

class _HeadlessHomePageState extends State<HeadlessHomePage> {
  final AppState state = AppState();
  int tabIndex = 1;

  @override
  void initState() {
    super.initState();
    state.initialize();
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final pages = <Widget>[
          ExploreTab(
              state: state, onOpenChat: () => setState(() => tabIndex = 1)),
          ChatTab(state: state),
          RecommendationsTab(state: state),
          HistoryTab(
              state: state, onOpenChat: () => setState(() => tabIndex = 1)),
          SettingsTab(state: state),
        ];

        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(child: pages[tabIndex]),
                    AppNavigationBar(
                      selectedIndex: tabIndex,
                      onDestinationSelected: (index) =>
                          setState(() => tabIndex = index),
                    ),
                  ],
                ),
                if (state.loading)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (state.error != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 8,
                    child: ErrorBanner(
                      message: state.error!,
                      onDismiss: state.clearError,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ChatTab extends StatefulWidget {
  const ChatTab({required this.state, super.key});

  final AppState state;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController inputController = TextEditingController();

  @override
  void dispose() {
    inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Column(
      children: [
        ChatHeader(state: state),
        Expanded(
          child: RefreshIndicator(
            onRefresh: state.selectedChat == null
                ? state.refresh
                : () => state.selectChat(state.selectedChat!),
            child: ChatMessageList(state: state),
          ),
        ),
        Composer(
          state: state,
          controller: inputController,
          onSend: () async {
            final text = inputController.text;
            inputController.clear();
            await state.sendUserMessage(text);
          },
        ),
      ],
    );
  }
}

class ChatHeader extends StatelessWidget {
  const ChatHeader({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final character = state.selectedCharacter;
    final provider = state.currentProvider;
    return Container(
      color: const Color(0xfff7f7f9),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: () {},
            icon: const Icon(Icons.arrow_back, size: 30),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => showCharacterSwitcher(context, state),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character?.name ?? '选择角色卡',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff3d3d42)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${state.chats.length} 个聊天 | ${providerLabel(provider)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 15, color: Color(0xff85858c)),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '新建聊天',
            onPressed:
                state.selectedCharacter == null ? null : state.createNewChat,
            icon: const Icon(Icons.add_circle_outline, size: 30),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 30),
            onSelected: (value) {
              switch (value) {
                case 'provider':
                  showProviderSheet(context, state);
                  break;
                case 'character':
                  showCharacterSwitcher(context, state);
                  break;
                case 'edit':
                  final character = state.selectedCharacter;
                  if (character != null) {
                    showCharacterEditor(context, state, character);
                  }
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'provider', child: Text('切换模型供应商')),
              PopupMenuItem(value: 'character', child: Text('切换角色卡')),
              PopupMenuItem(value: 'edit', child: Text('编辑角色卡')),
            ],
          ),
        ],
      ),
    );
  }
}

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final character = state.selectedCharacter;
    if (character == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          EmptyPanel(title: '尚未连接角色库', message: '请先在“我的”里设置 headless 后端地址。'),
        ],
      );
    }

    if (state.messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        children: [
          StarterCard(character: character),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: state.messages.length + (state.hasMoreBefore ? 1 : 0),
      itemBuilder: (context, index) {
        if (state.hasMoreBefore && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              onPressed: state.loadOlderMessages,
              icon: const Icon(Icons.expand_less),
              label:
                  Text('加载更早内容 (${state.loadedOffset}/${state.loadedTotal})'),
            ),
          );
        }

        final messageIndex = index - (state.hasMoreBefore ? 1 : 0);
        final message = state.messages[messageIndex];
        return MessageCard(
          message: message,
          index: messageIndex,
          onBranch: () => state.createBranchAt(messageIndex),
          onSwipe: message.hasSwipes
              ? (swipeId) => state.selectSwipeAt(messageIndex, swipeId)
              : null,
        );
      },
    );
  }
}

class StarterCard extends StatelessWidget {
  const StarterCard({required this.character, super.key});

  final CharacterCard character;

  @override
  Widget build(BuildContext context) {
    final content = [
      if (character.firstMessage.trim().isNotEmpty)
        character.firstMessage.trim(),
      if (character.description.trim().isNotEmpty) character.description.trim(),
    ].join('\n\n');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffe2e2e6)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x10000000), blurRadius: 18, offset: Offset(0, 8))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: content.isEmpty ? '- 当前状态：\n- 状态栏：开\n- 记忆区：开' : content,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(
                  fontSize: 19, height: 1.55, color: Color(0xff25262b)),
              listBullet:
                  const TextStyle(fontSize: 19, color: Color(0xff25262b)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Divider(thickness: 5, color: Color(0xffd8dbe0)),
          ),
          const Text(
            '请完善上述角色信息，或选择以下操作：',
            style:
                TextStyle(fontSize: 20, height: 1.45, color: Color(0xff25262b)),
          ),
          const SizedBox(height: 22),
          const Text.rich(
            TextSpan(
              style: TextStyle(
                  fontSize: 20, height: 1.65, color: Color(0xff25262b)),
              children: [
                TextSpan(text: '1. '),
                TextSpan(
                    text: '[自动生成]：',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' 由后端随机分配一个初始设定，立即开始游戏。\n'),
                TextSpan(text: '2. '),
                TextSpan(
                    text: '[手动填写]：',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' 打开角色卡编辑器补全信息。\n'),
                TextSpan(text: '3. '),
                TextSpan(
                    text: '[简易开场]：',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' 直接发送第一条消息开始。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MessageCard extends StatelessWidget {
  const MessageCard({
    required this.message,
    required this.index,
    required this.onBranch,
    required this.onSwipe,
    super.key,
  });

  final ChatMessage message;
  final int index;
  final VoidCallback onBranch;
  final ValueChanged<int>? onSwipe;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: isUser ? null : double.infinity,
        constraints: BoxConstraints(maxWidth: isUser ? 320 : double.infinity),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xffe9f6f8) : Colors.white,
          border: Border.all(color: const Color(0xffe1e1e5)),
          borderRadius: BorderRadius.circular(isUser ? 18 : 2),
          boxShadow: isUser
              ? null
              : const [
                  BoxShadow(
                      color: Color(0x0d000000),
                      blurRadius: 14,
                      offset: Offset(0, 6))
                ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    message.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xff777a82),
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Text(formatDate(message.sendDate),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xff9a9aa0))),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(
              data: message.text.isEmpty ? '[空消息]' : message.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                    fontSize: 17, height: 1.55, color: Color(0xff25262b)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (message.hasSwipes)
                  TextButton.icon(
                    onPressed: onSwipe == null
                        ? null
                        : () => showSwipeSheet(context, message, onSwipe!),
                    icon: const Icon(Icons.compare_arrows, size: 18),
                    label:
                        Text('${message.swipeId + 1}/${message.swipes.length}'),
                  ),
                IconButton(
                  tooltip: '创建分支',
                  onPressed: onBranch,
                  icon: const Icon(Icons.account_tree_outlined, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class Composer extends StatelessWidget {
  const Composer({
    required this.state,
    required this.controller,
    required this.onSend,
    super.key,
  });

  final AppState state;
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final provider = state.currentProvider;
    return Container(
      color: const Color(0xfff7f7f9),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '模型${provider?.model.isNotEmpty == true ? provider!.model : providerLabel(provider)}',
                  style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xff2f7f98),
                      fontWeight: FontWeight.w500),
                ),
                const Text('输入消耗384积分',
                    style: TextStyle(fontSize: 15, color: Color(0xff8d8d95))),
                const Text('输出消耗224积分',
                    style: TextStyle(fontSize: 15, color: Color(0xff8d8d95))),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                  tooltip: '复制',
                  onPressed: () {},
                  icon: const Icon(Icons.copy_outlined)),
              IconButton(
                  tooltip: '刷新',
                  onPressed: state.selectedChat == null
                      ? null
                      : () => state.selectChat(state.selectedChat!),
                  icon: const Icon(Icons.refresh)),
              IconButton(
                  tooltip: '编辑角色卡',
                  onPressed: state.selectedCharacter == null
                      ? null
                      : () => showCharacterEditor(
                          context, state, state.selectedCharacter!),
                  icon: const Icon(Icons.edit_outlined)),
              IconButton(
                  tooltip: '删除当前聊天',
                  onPressed: state.selectedChat == null
                      ? null
                      : () => state.deleteChat(state.selectedChat!),
                  icon: const Icon(Icons.delete_outline)),
              IconButton(
                  tooltip: '图片',
                  onPressed: () {},
                  icon: const Icon(Icons.image_outlined)),
              IconButton(
                  tooltip: '分支',
                  onPressed: state.messages.isEmpty
                      ? null
                      : () => state.createBranchAt(state.messages.length - 1),
                  icon: const Icon(Icons.account_tree_outlined)),
              IconButton(
                  tooltip: '统计',
                  onPressed: () {},
                  icon: const Icon(Icons.pie_chart_outline)),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: Text(
                    provider?.model.isNotEmpty == true
                        ? provider!.model
                        : providerLabel(provider),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: false,
                  avatar: const Icon(Icons.expand_more, size: 18),
                  onSelected: (_) => showProviderSheet(context, state),
                ),
              ),
              const SizedBox(width: 8),
              ActionChip(
                label: const Text('MOD广场'),
                onPressed: () {},
              ),
              const SizedBox(width: 8),
              ActionChip(
                avatar: Icon(
                    provider?.stream == true ? Icons.bolt : Icons.info_outline,
                    size: 18),
                label: Text(provider?.stream == true ? '流式' : '非流式'),
                onPressed: () {
                  final current = state.currentProvider;
                  if (current != null) {
                    state.updateProvider(
                      ProviderSelection(
                        provider: current.provider,
                        source: current.source,
                        model: current.model,
                        stream: !current.stream,
                        modelKey: current.modelKey,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: '开始你的第一次聊天吧',
              suffixIcon: IconButton(
                tooltip: '发送',
                onPressed: onSend,
                icon: const Icon(Icons.send_rounded),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xffdedee4))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xffdedee4))),
            ),
          ),
        ],
      ),
    );
  }
}

class ExploreTab extends StatelessWidget {
  const ExploreTab({required this.state, required this.onOpenChat, super.key});

  final AppState state;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      children: [
        const Text('探索',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (final character in state.characters)
          CharacterTile(
            state: state,
            character: character,
            onTap: () async {
              await state.selectCharacter(character);
              onOpenChat();
            },
          ),
      ],
    );
  }
}

class RecommendationsTab extends StatelessWidget {
  const RecommendationsTab({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('随机推荐',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (final character in state.characters.take(6))
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: panelDecoration(),
            child: Row(
              children: [
                CharacterAvatar(state: state, character: character, radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(character.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 17)),
                      Text(
                        character.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xff74747b)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class HistoryTab extends StatelessWidget {
  const HistoryTab({required this.state, required this.onOpenChat, super.key});

  final AppState state;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
          child: Row(
            children: [
              const Expanded(
                  child: Text('记录',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800))),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'date',
                      icon: Icon(Icons.calendar_today),
                      label: Text('日期')),
                  ButtonSegment(
                      value: 'size',
                      icon: Icon(Icons.data_usage),
                      label: Text('大小')),
                ],
                selected: {state.chatSort},
                onSelectionChanged: (value) =>
                    state.setChatSort(value.first, state.chatSortAscending),
              ),
              IconButton(
                tooltip: state.chatSortAscending ? '升序' : '降序',
                onPressed: () =>
                    state.setChatSort(state.chatSort, !state.chatSortAscending),
                icon: Icon(state.chatSortAscending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            itemCount: state.chats.length,
            itemBuilder: (context, index) {
              final chat = state.chats[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: panelDecoration(),
                child: ListTile(
                  onTap: () async {
                    await state.selectChat(chat);
                    onOpenChat();
                  },
                  title: Text(chat.fileId,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${formatDate(chat.lastMessageAt ?? chat.updatedAt)} | ${chat.fileSize} | ${chat.chatItems} 条\n${chat.preview}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: '删除',
                    onPressed: () => state.deleteChat(chat),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({required this.state, super.key});

  final AppState state;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController serverController;

  @override
  void initState() {
    super.initState();
    serverController = TextEditingController(text: widget.state.serverUrl);
  }

  @override
  void didUpdateWidget(covariant SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (serverController.text != widget.state.serverUrl) {
      serverController.text = widget.state.serverUrl;
    }
  }

  @override
  void dispose() {
    serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      children: [
        const Text('我的',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('后端服务器',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: serverController,
                decoration: const InputDecoration(
                  hintText: 'http://127.0.0.1:8000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => state.setServerUrl(serverController.text),
                icon: const Icon(Icons.cloud_sync_outlined),
                label: const Text('保存并重新连接'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前用户：${state.bootstrap?.userName ?? '-'}'),
              Text('API：${state.bootstrap?.version ?? '-'}'),
              Text('公网入口：${state.bootstrap?.remotePublicUrl ?? '-'}'),
            ],
          ),
        ),
      ],
    );
  }
}

class CharacterTile extends StatelessWidget {
  const CharacterTile({
    required this.state,
    required this.character,
    required this.onTap,
    super.key,
  });

  final AppState state;
  final CharacterCard character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedCharacter?.avatar == character.avatar;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: panelDecoration(selected: selected),
      child: ListTile(
        onTap: onTap,
        leading: CharacterAvatar(state: state, character: character),
        title:
            Text(character.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(character.description,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: '编辑',
          onPressed: () => showCharacterEditor(context, state, character),
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }
}

class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({
    required this.state,
    required this.character,
    this.radius = 22,
    super.key,
  });

  final AppState state;
  final CharacterCard character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final thumbnail = character.thumbnailUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xffe8e8ee),
      foregroundImage: thumbnail.isEmpty
          ? null
          : NetworkImage(state.api.mediaUrl(thumbnail),
              headers: state.api.imageHeaders),
      child: thumbnail.isEmpty
          ? Text(character.name.isEmpty ? '?' : character.name.substring(0, 1))
          : null,
    );
  }
}

class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      height: 76,
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore),
            label: '探索'),
        NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '聊天'),
        NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: '随机推荐'),
        NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '记录'),
        NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的'),
      ],
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({required this.title, required this.message, super.key});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: Color(0xff77777e))),
        ],
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(
      {required this.message, required this.onDismiss, super.key});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xffffefef),
          border: Border.all(color: const Color(0xffffc5c5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xffb3261e)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message,
                    maxLines: 3, overflow: TextOverflow.ellipsis)),
            IconButton(onPressed: onDismiss, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}

void showCharacterSwitcher(BuildContext context, AppState state) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const Text('切换角色卡',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final character in state.characters)
            CharacterTile(
              state: state,
              character: character,
              onTap: () async {
                Navigator.pop(context);
                await state.selectCharacter(character);
              },
            ),
        ],
      );
    },
  );
}

void showProviderSheet(BuildContext context, AppState state) {
  final catalog = state.providerCatalog;
  final current = catalog?.current;
  if (catalog == null || current == null) {
    return;
  }

  var provider = current.provider;
  var source = current.source;
  var model = current.model;
  var stream = current.stream;
  final modelController = TextEditingController(text: model);

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final providerOption = catalog.providers.firstWhere(
            (item) => item.id == provider,
            orElse: () => catalog.providers.first,
          );
          final sources = providerOption.sources;
          if (sources.isNotEmpty && !sources.contains(source)) {
            source = sources.first;
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('模型供应商',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: provider,
                  decoration: const InputDecoration(
                      labelText: 'Provider', border: OutlineInputBorder()),
                  items: catalog.providers
                      .map((item) => DropdownMenuItem(
                          value: item.id, child: Text(item.label)))
                      .toList(),
                  onChanged: (value) => setModalState(() {
                    provider = value ?? provider;
                    final nextProvider = catalog.providers
                        .firstWhere((item) => item.id == provider);
                    source = nextProvider.sources.isEmpty
                        ? ''
                        : nextProvider.sources.first;
                  }),
                ),
                const SizedBox(height: 12),
                if (sources.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: source,
                    decoration: const InputDecoration(
                        labelText: 'Source', border: OutlineInputBorder()),
                    items: sources
                        .map((item) =>
                            DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) =>
                        setModalState(() => source = value ?? source),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelController,
                  decoration: const InputDecoration(
                      labelText: 'Model ID', border: OutlineInputBorder()),
                  onChanged: (value) => model = value,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('流式输出'),
                  value: stream,
                  onChanged: (value) => setModalState(() => stream = value),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    await state.updateProvider(
                      ProviderSelection(
                        provider: provider,
                        source: source,
                        model: modelController.text.trim(),
                        stream: stream,
                        modelKey: current.modelKey,
                      ),
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('应用'),
                ),
              ],
            ),
          );
        },
      );
    },
  ).whenComplete(modelController.dispose);
}

void showSwipeSheet(
    BuildContext context, ChatMessage message, ValueChanged<int> onSwipe) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: message.swipes.length,
        itemBuilder: (context, index) {
          return ListTile(
            selected: index == message.swipeId,
            title:
                Text('#${index + 1}${index == message.swipeId ? ' 当前' : ''}'),
            subtitle: Text(message.swipes[index],
                maxLines: 3, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(context);
              onSwipe(index);
            },
          );
        },
      );
    },
  );
}

void showCharacterEditor(
    BuildContext context, AppState state, CharacterCard character) {
  final name = TextEditingController(text: character.name);
  final description = TextEditingController(text: character.description);
  final personality = TextEditingController(text: character.personality);
  final scenario = TextEditingController(text: character.scenario);
  final firstMessage = TextEditingController(text: character.firstMessage);
  final messageExample = TextEditingController(text: character.messageExample);
  final creatorNotes = TextEditingController(text: character.creatorNotes);
  final tags = TextEditingController(text: character.tags.join(', '));

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
            18, 0, 18, MediaQuery.of(context).viewInsets.bottom + 18),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('角色卡',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            editorField(name, '名称', maxLines: 1),
            editorField(description, '描述'),
            editorField(personality, '性格'),
            editorField(scenario, '场景'),
            editorField(firstMessage, '第一条消息'),
            editorField(messageExample, '对话示例'),
            editorField(creatorNotes, '创作者备注'),
            editorField(tags, '标签，逗号分隔', maxLines: 1),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                final updated = character.copyWith(
                  name: name.text.trim(),
                  description: description.text,
                  personality: personality.text,
                  scenario: scenario.text,
                  firstMessage: firstMessage.text,
                  messageExample: messageExample.text,
                  creatorNotes: creatorNotes.text,
                  tags: tags.text
                      .split(',')
                      .map((tag) => tag.trim())
                      .where((tag) => tag.isNotEmpty)
                      .toList(),
                );
                await state.saveCharacter(updated);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存角色卡'),
            ),
          ],
        ),
      );
    },
  ).whenComplete(() {
    name.dispose();
    description.dispose();
    personality.dispose();
    scenario.dispose();
    firstMessage.dispose();
    messageExample.dispose();
    creatorNotes.dispose();
    tags.dispose();
  });
}

Widget editorField(TextEditingController controller, String label,
    {int maxLines = 4}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );
}

BoxDecoration panelDecoration({bool selected = false}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
        color: selected ? const Color(0xff2f7f98) : const Color(0xffe2e2e6)),
    boxShadow: const [
      BoxShadow(color: Color(0x0a000000), blurRadius: 10, offset: Offset(0, 4))
    ],
  );
}

String providerLabel(ProviderSelection? provider) {
  if (provider == null) {
    return '未连接';
  }
  return [
    provider.provider,
    if (provider.source.isNotEmpty) provider.source,
    if (provider.model.isNotEmpty) provider.model,
  ].join(' / ');
}

String formatDate(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
}
