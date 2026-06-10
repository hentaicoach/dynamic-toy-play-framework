class ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  final bool hasPreview;
  final bool isLoading;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.hasPreview = false,
    this.isLoading = false,
  }) : timestamp = timestamp ?? DateTime.now();
}
