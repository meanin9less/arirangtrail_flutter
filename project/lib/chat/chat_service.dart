import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import './chat_model.dart';

class ChatService {
  final int roomId;
  final String jwtToken;
  final String senderId;
  final String senderNickname;

  // 🔍 디버깅: 고유 ID 생성
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();

  StompClient? _stompClient;
  void Function()? _unsubscribeCallback;

  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isDisposed = false;

  final _messageController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get messageStream => _messageController.stream;

  ChatService({
    required this.roomId,
    required this.jwtToken,
    required this.senderId,
    required this.senderNickname,
  }) {
    // 🔍 디버깅 포인트 1: 객체 생성 추적
    print("🏗️ [ChatService-$_instanceId] 새 인스턴스 생성 - Room:$roomId, Sender:$senderId");
  }

  void connect() {
    // 🔍 디버깅 포인트 2: 연결 시도 추적
    print("🔗 [ChatService-$_instanceId] connect() 호출 - 현재 상태: connecting=$_isConnecting, connected=$_isConnected, disposed=$_isDisposed");

    if (_isConnecting || _isConnected || _isDisposed) {
      print("⚠️ [ChatService-$_instanceId] 연결 요청 무시됨!");
      return;
    }

    _isConnecting = true;

    final wsUrl = dotenv.env['PROD_WS_FLUTTER_URL'];
    if (wsUrl == null) {
      print("❌ [ChatService-$_instanceId] PROD_WS_FLUTTER_URL 없음");
      _isConnecting = false;
      return;
    }

    print("🌐 [ChatService-$_instanceId] 웹소켓 URL: $wsUrl");
    final pureToken = jwtToken.startsWith('Bearer ') ? jwtToken.substring(7) : jwtToken;
    print("🔑 [ChatService-$_instanceId] 토큰 길이: ${pureToken.length}");

    if (_stompClient != null) {
      print("♻️ [ChatService-$_instanceId] 기존 연결 정리 중...");
      _cleanup();
    }

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: _onConnectCallback,
        onWebSocketError: (dynamic error) {
          print("❌ [ChatService-$_instanceId] 웹소켓 오류: $error");
          _isConnecting = false;
          _isConnected = false;
        },
        onStompError: (StompFrame frame) {
          print("❌ [ChatService-$_instanceId] STOMP 오류: ${frame.body}");
          _isConnecting = false;
          _isConnected = false;
        },
        onDisconnect: (StompFrame frame) {
          print("⚠️ [ChatService-$_instanceId] 연결 끊어짐: ${frame.body}");
          _isConnected = false;
          _isConnecting = false;
        },
        stompConnectHeaders: {
          'Authorization': 'Bearer $pureToken',
        },
        webSocketConnectHeaders: {
          'Authorization': 'Bearer $pureToken',
        },
      ),
    );

    print("⚡ [ChatService-$_instanceId] StompClient 활성화 시도...");
    _stompClient!.activate();
  }

  void _onConnectCallback(StompFrame frame) {
    // 🔍 디버깅 포인트 3: 연결 성공 추적
    print("🎉 [ChatService-$_instanceId] STOMP 연결 성공! 구독 시작...");

    if (_isDisposed) {
      print("⚠️ [ChatService-$_instanceId] 이미 해제된 서비스 - 연결 콜백 무시");
      return;
    }

    _isConnecting = false;
    _isConnected = true;

    _unsubscribeCallback?.call();

    final destination = '/sub/chat/room/$roomId';
    print("📡 [ChatService-$_instanceId] 구독 시작: $destination");

    _unsubscribeCallback = _stompClient?.subscribe(
      destination: destination,
      callback: (frame) {
        // 🔍 디버깅 포인트 4: 메시지 수신 추적 (가장 중요!)
        print("📨 [ChatService-$_instanceId] RAW 메시지 수신!");
        print("📄 [ChatService-$_instanceId] 메시지 본문: ${frame.body}");

        if (_isDisposed) {
          print("⚠️ [ChatService-$_instanceId] 이미 해제된 서비스 - 메시지 수신 무시");
          return;
        }

        if (frame.body != null) {
          try {
            final jsonData = json.decode(frame.body!);
            print("🔍 [ChatService-$_instanceId] 파싱된 JSON: $jsonData");

            final chatMessage = ChatMessage.fromJson(jsonData);
            print("✅ [ChatService-$_instanceId] ChatMessage 생성 완료:");
            print("   - Type: ${chatMessage.type}");
            print("   - Sender: ${chatMessage.sender}");
            print("   - Message: ${chatMessage.message}");
            print("   - MessageSeq: ${chatMessage.messageSeq}");
            print("   - My ID: $senderId");
            print("   - Is My Message: ${chatMessage.sender == senderId}");

            if (!_messageController.isClosed) {
              _messageController.add(chatMessage);
              print("📤 [ChatService-$_instanceId] 메시지 스트림에 추가 완료");
            } else {
              print("❌ [ChatService-$_instanceId] 메시지 컨트롤러가 닫혀있음!");
            }
          } catch (e) {
            print("❌ [ChatService-$_instanceId] 메시지 파싱 에러: $e");
            print("❌ [ChatService-$_instanceId] 원본 데이터: ${frame.body}");
          }
        }
      },
    );

    print("✅ [ChatService-$_instanceId] 구독 설정 완료");
  }

  void sendMessage(String messageContent) {
    // 🔍 디버깅 포인트 5: 메시지 전송 추적
    print("📝 [ChatService-$_instanceId] sendMessage 호출: '$messageContent'");
    print("🔍 [ChatService-$_instanceId] 전송 가능 여부 확인:");
    print("   - _isDisposed: $_isDisposed");
    print("   - _stompClient != null: ${_stompClient != null}");
    print("   - _stompClient.connected: ${_stompClient?.connected ?? false}");

    if (_isDisposed) {
      print("❌ [ChatService-$_instanceId] 해제된 서비스 - 전송 실패");
      return;
    }

    if (_stompClient == null || !_stompClient!.connected) {
      print("❌ [ChatService-$_instanceId] 연결 안됨 - 전송 실패");
      return;
    }

    final messagePayload = {
      'type': 'TALK',
      'roomId': roomId,
      'sender': senderId,
      'nickname': senderNickname,
      'message': messageContent,
    };

    print("📦 [ChatService-$_instanceId] 전송할 페이로드: $messagePayload");

    try {
      _stompClient!.send(
        destination: '/api/pub/chat/message',
        body: json.encode(messagePayload),
        headers: {'content-type': 'application/json'},
      );
      print("✅ [ChatService-$_instanceId] 서버로 전송 완료");
    } catch (e) {
      print("❌ [ChatService-$_instanceId] 전송 중 에러: $e");
    }
  }

  void _cleanup() {
    print("🧹 [ChatService-$_instanceId] _cleanup 시작...");

    _unsubscribeCallback?.call();
    _unsubscribeCallback = null;
    print("   - 구독 해제 완료");

    _stompClient?.deactivate();
    _stompClient = null;
    print("   - StompClient 해제 완료");

    _isConnected = false;
    _isConnecting = false;
    print("   - 상태 초기화 완료");
  }

  void dispose() {
    // 🔍 디버깅 포인트 6: 객체 해제 추적
    print("💀 [ChatService-$_instanceId] dispose 호출");

    if (_isDisposed) {
      print("⚠️ [ChatService-$_instanceId] 이미 해제된 서비스");
      return;
    }

    _isDisposed = true;
    print("🔄 [ChatService-$_instanceId] 서비스 정리 시작...");

    _cleanup();

    if (!_messageController.isClosed) {
      _messageController.close();
      print("   - 메시지 컨트롤러 닫기 완료");
    }

    print("✅ [ChatService-$_instanceId] 서비스 정리 완료");
  }
}