// ChatScreen.dart (생명주기 관리 최종 수정안)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:project/widget/translator.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../provider/auth_provider.dart';
import 'chat_model.dart';
import 'chat_api_service.dart';
import 'chat_service.dart';

class ChatScreen extends StatefulWidget {
  final int roomId;
  final String roomName;

  const ChatScreen({Key? key, required this.roomId, required this.roomName})
      : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final String _screenId = DateTime.now().millisecondsSinceEpoch.toString();
  final List<ChatMessage> _messages = [];
  bool _isLoadingHistory = true;
  final TextEditingController _textController = TextEditingController();
  late String myUserId;
  int _lastReadSeq = 0;

  // ✨ 1. late final을 제거하고 nullable(?)로 선언하여 생명주기를 완벽하게 제어합니다.
  ChatService? _chatService;
  StreamSubscription<ChatMessage>? _messageSubscription;
  final List<ChatMessage> _pendingMessages = [];

  @override
  void initState() {
    super.initState();
    print("🏁 [ChatScreen-$_screenId] initState - Room: ${widget.roomId}");
    // 첫 프레임 렌더링 후 안전하게 초기화 메서드를 호출합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  // --- 채팅 초기화를 담당하는 단일 함수 ---
  Future<void> _initializeChat() async {
    if (_chatService != null) {
      print("⚠️ [ChatScreen-$_screenId] 이미 초기화됨. 중복 실행 방지.");
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    myUserId = authProvider.userProfile?.username ?? '';
    final token = authProvider.token;

    if (token == null) {
      if (mounted) setState(() => _isLoadingHistory = false);
      return;
    }

    _chatService = ChatService(
      roomId: widget.roomId,
      jwtToken: token,
      senderId: myUserId,
      senderNickname: authProvider.userProfile?.nickname ?? '알수없음',
    );

    _messageSubscription = _chatService!.messageStream.listen(_onNewMessage);
    _chatService!.connect();
    await _fetchChatHistory();

    // ✅ 2. 히스토리 로딩 후 대기 중인 메시지들 처리
    _processPendingMessages();
  }

  // ✅ 3. 마운트되지 않은 상태에서 받은 메시지들을 처리
  void _processPendingMessages() {
    if (_pendingMessages.isNotEmpty && mounted) {
      print("📦 [ChatScreen-$_screenId] 대기 중인 메시지 ${_pendingMessages.length}개 처리");

      setState(() {
        for (final pendingMessage in _pendingMessages) {
          final isDuplicate = _messages.any((msg) =>
          msg.messageSeq != null &&
              pendingMessage.messageSeq != null &&
              msg.messageSeq == pendingMessage.messageSeq);

          if (!isDuplicate) {
            print("   ✅ 대기 메시지 추가: Seq=${pendingMessage.messageSeq}, Msg='${pendingMessage.message}'");
            _messages.insert(0, pendingMessage);

            if (pendingMessage.messageSeq != null && pendingMessage.messageSeq! > _lastReadSeq) {
              _lastReadSeq = pendingMessage.messageSeq!;
            }
          } else {
            print("   🚫 대기 메시지 중복: Seq=${pendingMessage.messageSeq}");
          }
        }
        _pendingMessages.clear(); // 처리 완료 후 큐 비우기
      });
    }
  }

  // --- 실시간 메시지 수신 처리 ---
// --- 실시간 메시지 수신 처리 (디버깅 로그 추가) ---
  // _onNewMessage도 확인
// ✅ 4. 메시지 수신 처리 - 마운트 상태에 따라 분기
  void _onNewMessage(ChatMessage newMessage) {
    print("🔔 [ChatScreen-$_screenId] 메시지수신: Seq=${newMessage.messageSeq}, '${newMessage.message}', mounted=$mounted");

    if (!mounted) {
      // ✅ 마운트되지 않았을 때는 대기 큐에 저장
      print("   📥 UNMOUNTED! 메시지를 대기 큐에 저장");
      _pendingMessages.add(newMessage);
      return;
    }

    // ✅ 마운트된 상태에서는 즉시 처리
    _processMessage(newMessage);
  }

  void _processMessage(ChatMessage newMessage) {
    setState(() {
      // 🔍 현재 메시지들과 대기 큐 모두에서 중복 체크
      final isDuplicateInMessages = _messages.any((msg) =>
      msg.messageSeq != null &&
          newMessage.messageSeq != null &&
          msg.messageSeq == newMessage.messageSeq);

      final isDuplicateInPending = _pendingMessages.any((msg) =>
      msg.messageSeq != null &&
          newMessage.messageSeq != null &&
          msg.messageSeq == newMessage.messageSeq);

      final isDuplicate = isDuplicateInMessages || isDuplicateInPending;

      print("   🔍 중복체크: Messages=$isDuplicateInMessages, Pending=$isDuplicateInPending, Final=$isDuplicate");

      if (!isDuplicate) {
        print("   ✅ 새 메시지 추가: '${newMessage.message}'");
        _messages.insert(0, newMessage);

        if (newMessage.messageSeq != null && newMessage.messageSeq! > _lastReadSeq) {
          _lastReadSeq = newMessage.messageSeq!;
        }

        // 🔍 현재 메시지 상태 출력f
        print("   📋 현재 메시지들 (최신 3개):");
        for (int i = 0; i < _messages.length && i < 3; i++) {
          print("      [$i] Seq=${_messages[i].messageSeq}, Msg='${_messages[i].message}'");
        }
      } else {
        print("   🚫 중복 메시지 무시");
      }
    });
  }

// --- 과거 메시지 로딩 (디버깅 로그 추가) ---
  Future<void> _fetchChatHistory() async {
    print("📜 [ChatScreen-$_screenId] _fetchChatHistory 시작");

    try {
      final history = await ChatApiService.getChatHistory(widget.roomId);

      print("   📥 API 히스토리: ${history.length}개");

      if (!mounted) return;

      if (history.isNotEmpty) {
        _lastReadSeq = history.first.messageSeq ?? 0; // DESC라서 first가 최신
      }

      setState(() {
        _messages.addAll(history.reversed); // API가 DESC이므로 reversed
        _isLoadingHistory = false;

        print("   📈 히스토리 로딩 완료: ${_messages.length}개");
      });

    } catch (e) {
      print("   ❌ 히스토리 로딩 에러: $e");
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

// --- 메시지 전송 (디버깅 로그 추가) ---
  void _handleSendPressed() {
    final text = _textController.text.trim();
    print("📤 [ChatScreen-$_screenId] 메시지 전송: '$text', mounted=$mounted");

    if (text.isNotEmpty) {
      _chatService?.sendMessage(text);
      _textController.clear();
    }
  }
  // --- 3. 화면 해제 시 모든 자원을 깨끗하게 정리합니다. ---
  @override
  void dispose() {
    print("💀 [ChatScreen-$_screenId] dispose 시작");
    print("   📦 대기 중인 메시지: ${_pendingMessages.length}개");

    if (_lastReadSeq > 0) {
      ChatApiService.updateLastReadSequence(widget.roomId, myUserId, _lastReadSeq);
    }

    _messageSubscription?.cancel();
    _chatService?.dispose();
    _textController.dispose();
    _pendingMessages.clear(); // 대기 큐 정리

    super.dispose();
    print("✅ [ChatScreen-$_screenId] dispose 완료");
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // 🔍 빌드 상태 확인
    if (_messages.length > 0) {
      print("🎨 [ChatScreen-$_screenId] build 호출 - 메시지 ${_messages.length}개 렌더링");
    }

    return Scaffold(
      appBar: AppBar(
        title: TranslatedText(text: "${widget.roomName} (Debug-$_screenId)"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 🔍 디버그 정보 표시
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.yellow[100],
            child: Text(
              "🔍 Debug: 메시지 ${_messages.length}개, LastReadSeq: $_lastReadSeq",
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(child: Text(l10n.chatMessage))
                : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMe = message.sender == myUserId;

                // 🔍 렌더링 시점의 상세 로그 (처음 5개만)
                if (index < 5) {
                  print("🎨 [ChatScreen-$_screenId] ListView.builder [$index/${_messages.length}]:");
                  print("    Seq: ${message.messageSeq}");
                  print("    Sender: ${message.sender} ${isMe ? '(나)' : '(상대방)'}");
                  print("    Message: '${message.message}'");
                  print("    Type: ${message.type}");
                }
                switch (message.type) {
                  case MessageType.TALK:
                  case MessageType.IMAGE:
                    return _buildTalkBubble(message, isMe: isMe);
                  case MessageType.ENTER:
                  case MessageType.LEAVE:
                    return _buildSystemMessage(message);
                  default:
                    return const SizedBox.shrink();
                }
              },
            ),
          ),
          _buildMessageComposer(l10n),
        ],
      ),
    );
  }

  Widget _buildMessageComposer(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration.collapsed(
                hintText: l10n.chatHintText,
              ),
              onSubmitted: (_) => _handleSendPressed(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _handleSendPressed,
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(ChatMessage message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: TranslatedText(
            text: message.message, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildTalkBubble(ChatMessage message, {required bool isMe}) {
    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 64.0 : 16.0,
        right: isMe ? 16.0 : 64.0,
        top: 8,
        bottom: 8,
      ),
      child: Column(
        crossAxisAlignment:
        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            TranslatedText(
              text: message.nickname ?? '알수없음',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue[100] : Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔍 디버그 정보 표시
                Text(
                  "Seq:${message.messageSeq} ${isMe ? '(Me)' : '(Other)'}",
                  style: const TextStyle(fontSize: 8, color: Colors.red),
                ),
                const SizedBox(height: 2),
                message.type == MessageType.IMAGE
                    ? Image.network(message.message)
                    : TranslatedText(text: message.message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}