import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

class LobbyService {
  final Function onLobbyUpdate;
  final String jwtToken;

  StompClient? _stompClient;
  void Function()? _unsubscribeCallback;

  // ✨ 연결 상태 추적 변수 추가
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isDisposed = false;

  LobbyService({required this.onLobbyUpdate, required this.jwtToken});

  void connectAndSubscribe() {
    // ✨ 중복 연결 방지
    if (_isConnecting || _isConnected || _isDisposed) {
      print("⚠️ [LobbyService] 이미 연결 중이거나 연결됨 또는 해제됨. 연결 요청 무시.");
      return;
    }

    _isConnecting = true;

    final wsUrl = dotenv.env['PROD_WS_FLUTTER_URL'];
    if (wsUrl == null) {
      print("❌ [LobbyService] PROD_WS_FLUTTER_URL을 .env 파일에서 찾을 수 없습니다.");
      _isConnecting = false;
      return;
    }

    final pureToken = jwtToken.startsWith('Bearer ') ? jwtToken.substring(7) : jwtToken;

    // ✨ 기존 연결이 있다면 먼저 정리
    if (_stompClient != null) {
      _cleanup();
    }

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: _onConnectCallback,
        stompConnectHeaders: {'Authorization': 'Bearer $pureToken'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $pureToken'},
        onWebSocketError: (dynamic error) {
          print("❌ [LobbyService] 웹소켓 오류: $error");
          _isConnecting = false;
          _isConnected = false;
        },
        onStompError: (StompFrame frame) {
          print("❌ [LobbyService] STOMP 오류: ${frame.body}");
          _isConnecting = false;
          _isConnected = false;
        },
        onDisconnect: (StompFrame frame) {
          print("⚠️ [LobbyService] 웹소켓 연결 끊어짐.");
          _isConnected = false;
          _isConnecting = false;
        },
      ),
    );

    print("✅ [LobbyService] StompClient 활성화 시도...");
    _stompClient!.activate();
  }

  void _onConnectCallback(StompFrame frame) {
    if (_isDisposed) {
      print("⚠️ [LobbyService] 이미 해제된 서비스. 연결 콜백 무시.");
      return;
    }

    _isConnecting = false;
    _isConnected = true;

    print("🎉 [LobbyService] STOMP 연결 성공! 로비 구독을 시작합니다.");

    // ✨ 기존 구독이 있다면 해제
    _unsubscribeCallback?.call();

    _unsubscribeCallback = _stompClient?.subscribe(
      destination: '/sub/chat/lobby',
      callback: (frame) {
        if (_isDisposed) {
          print("⚠️ [LobbyService] 이미 해제된 서비스. 메시지 수신 무시.");
          return;
        }

        print("📨 [LobbyService] 메시지 수신!");
        try {
          final data = json.decode(frame.body!);
          if (data['type'] == 'LOBBY_ROOM_UPDATE') {
            print("✅ [LobbyService] 로비 업데이트 신호 수신!");
            onLobbyUpdate();
          }
        } catch(e) {
          print("❌ [LobbyService] 메시지 파싱 에러: $e");
        }
      },
    );
  }

  // ✨ 내부 정리 메서드
  void _cleanup() {
    _unsubscribeCallback?.call();
    _unsubscribeCallback = null;

    _stompClient?.deactivate();
    _stompClient = null;

    _isConnected = false;
    _isConnecting = false;
  }

  void dispose() {
    if (_isDisposed) {
      print("⚠️ [LobbyService] 이미 해제된 서비스.");
      return;
    }

    print("🔄 [LobbyService] 서비스 정리 시작...");
    _isDisposed = true;

    _cleanup();

    print("✅ [LobbyService] 서비스 정리 완료.");
  }
}