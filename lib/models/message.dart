class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String? content;
  final String type;
  final String? mediaUrl;
  final String? replyToId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isRead;
  final bool isDeleted;
  final bool forwarded;
  final bool decryptFailed;
  final Map<String, dynamic>? mediaSecret;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.content,
    this.type = 'text',
    this.mediaUrl,
    this.replyToId,
    required this.createdAt,
    this.editedAt,
    this.isRead = false,
    this.isDeleted = false,
    this.forwarded = false,
    this.decryptFailed = false,
    this.mediaSecret,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      content: json['content'] as String?,
      type: (json['type'] as String?) ?? 'text',
      mediaUrl: json['media_url'] as String?,
      replyToId: json['reply_to']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      editedAt: json['edited_at'] != null
          ? DateTime.tryParse(json['edited_at'].toString())
          : null,
      isRead: json['is_read'] as bool? ?? false,
      isDeleted: json['is_deleted'] as bool? ?? false,
      forwarded: json['forwarded'] as bool? ?? false,
      decryptFailed: json['decrypt_failed'] as bool? ?? false,
      mediaSecret: json['media_secret'] is Map
          ? Map<String, dynamic>.from(json['media_secret'] as Map)
          : null,
    );
  }
}
