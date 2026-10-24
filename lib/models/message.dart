class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String? content;
  final String type; // text, image, video, voice, file
  final String? mediaUrl;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.content,
    this.type = 'text',
    this.mediaUrl,
    required this.createdAt,
  });

  // Supabase'den gelen JSON verisini modele çevirir
  // Null safety için her alana varsayılan değer eklenmiştir.
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      content: json['content'] as String?,
      type: (json['type'] as String?) ?? 'text',
      mediaUrl: json['media_url'] as String?,
      createdAt: json['created_at'] != null 
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  // Modele yeni bir mesaj yazarken kullanılır
  Map<String, dynamic> toJson() {
    return {
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'type': type,
      'media_url': mediaUrl,
    };
  }

  // Kopyalama metodu (Optimistic UI için gerektiğinde kullanılır)
  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    String? type,
    String? mediaUrl,
    DateTime? createdAt,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
