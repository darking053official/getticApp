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
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      conversationId: json['conversation_id'],
      senderId: json['sender_id'],
      content: json['content'],
      type: json['type'] ?? 'text',
      mediaUrl: json['media_url'],
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
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
}
