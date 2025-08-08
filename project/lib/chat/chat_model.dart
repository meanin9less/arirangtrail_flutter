// 1. 서버의 MessageType과 동일한 enum을 Dart에서도 정의합니다.
//    이렇게 하면 'ENTER' 같은 문자열을 직접 쓰는 것보다 훨씬 안전합니다.
class ChatRoom {
  final int id; // Long 타입은 Dart의 int로 받을 수 있습니다.
  final String title;
  final String? subject; // subject는 null일 수 있으므로 String?
  final String creator; // 생성자 ID (예: 'aaa')
  final String creatorNickname; // 생성자 닉네임 (예: '에이스')
  final DateTime meetingDate;
  final int participantCount;
  final int maxParticipants;
  final int unreadCount;

  ChatRoom({
    required this.id,
    required this.title,
    this.subject,
    required this.creator,
    required this.creatorNickname,
    required this.meetingDate,
    required this.participantCount,
    required this.maxParticipants,
    required this.unreadCount,
  });

  // 서버에서 온 JSON(Map)을 이 ChatRoom 클래스 틀에 맞춰 변환해주는 '공장'
  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'],
      title: json['title'],
      subject: json['subject'], // subject는 없을 수도 있으니 그대로 받음
      creator: json['creator'],
      creatorNickname: json['creatorNickname'],
      // 서버의 LocalDateTime 문자열을 Dart의 DateTime 객체로 변환
      meetingDate: DateTime.parse(json['meetingDate']),
      participantCount: json['participantCount'],
      maxParticipants: json['maxParticipants'],
      unreadCount: json['unreadCount'],
    );
  }
}

enum MessageType {
  ENTER,
  TALK,
  LEAVE,
  IMAGE,
  UNKNOWN // 혹시 모를 다른 타입에 대비
}

// 2. 새로운 ChatMessage 모델
class ChatMessage {
  final MessageType type;
  final String? sender;// 메시지 타입 (입장, 대화, 퇴장 등)
  final String? nickname;     // 보낸 사람 닉네임 (TALK, IMAGE 메시지에만 존재)
  final String message;        // 메시지 내용 또는 시스템 메시지
  final int? messageSeq;

  // final DateTime timestamp; // DTO에 타임스탬프가 없으므로 일단 제외. 필요 시 추가해야 함.

  ChatMessage({
    required this.type,
    this.sender,
    this.nickname,
    required this.message,
    this.messageSeq
  });

  // 3. 실제 DTO를 파싱하는 똑똑한 '공장(factory)'
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // 서버에서 온 messageType 문자열을 Dart의 MessageType enum으로 변환
    MessageType type;
    switch (json['type']) {
      case 'ENTER':
        type = MessageType.ENTER;
        break;
      case 'TALK':
        type = MessageType.TALK;
        break;
      case 'LEAVE':
        type = MessageType.LEAVE;
        break;
      case 'IMAGE':
        type = MessageType.IMAGE;
        break;
      default:
        type = MessageType.UNKNOWN; // 알 수 없는 타입 처리
    }

    return ChatMessage(
      type: type,
      nickname: json['nickname'], // 서버 DTO의 'nickname' 필드를 그대로 사용
      sender: json['sender'],
      message: json['message'],   // 서버 DTO의 'message' 필드를 그대로 사용
      messageSeq: json['messageSeq']
    );
  }
}