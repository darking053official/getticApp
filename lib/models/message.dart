class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String? content;
  final String type;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.content,
    this.type = 'text',
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      conversationId: json['conversation_id'],
      senderId: json['sender_id'],
      content: json['content'],
      type: json['type'] ?? 'text',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
