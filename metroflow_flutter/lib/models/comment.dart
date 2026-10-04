import 'reaction.dart';

class Mention {
  final String type;
  final String id;

  Mention({
    required this.type,
    required this.id,
  });

  factory Mention.fromJson(Map<String, dynamic> json) {
    return Mention(
      type: (json['type'] as String?) ?? '',
      id: (json['id'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'id': id,
    };
  }
}

class Comment {
  final String id;
  final String? taskId;
  final String? epicName;
  final String? epicId;
  final String userId;
  final String? userName;
  final String? userEmail;
  final String? parentCommentId;
  final String content;
  final List<Mention> mentions;
  final List<Comment>? replies;
  final List<Reaction>? reactions;
  final String createdAt;
  final String updatedAt;

  Comment({
    required this.id,
    this.taskId,
    this.epicName,
    this.epicId,
    required this.userId,
    this.userName,
    this.userEmail,
    this.parentCommentId,
    required this.content,
    required this.mentions,
    this.replies,
    this.reactions,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: (json['id'] as String?) ?? '',
      taskId: json['taskId'] as String?,
      epicName: json['epicName'] as String?,
      epicId: json['epicId'] as String?,
      userId: (json['userId'] as String?) ?? '',
      userName: json['userName'] as String?,
      userEmail: json['userEmail'] as String?,
      parentCommentId: json['parentCommentId'] as String?,
      content: (json['content'] as String?) ?? '',
      mentions: (json['mentions'] as List?)
              ?.map((e) {
                try {
                  return Mention.fromJson(e as Map<String, dynamic>);
                } catch (e) {
                  return null;
                }
              })
              .whereType<Mention>()
              .toList() ??
          [],
      replies: json['replies'] != null
          ? (json['replies'] as List<dynamic>)
              .map((e) {
                try {
                  return Comment.fromJson(e as Map<String, dynamic>);
                } catch (e) {
                  return null;
                }
              })
              .whereType<Comment>()
              .toList()
          : null,
      reactions: json['reactions'] != null
          ? (json['reactions'] as List<dynamic>)
              .map((e) {
                try {
                  return Reaction.fromJson(e as Map<String, dynamic>);
                } catch (e) {
                  return null;
                }
              })
              .whereType<Reaction>()
              .toList()
          : null,
      createdAt: (json['createdAt'] as String?) ?? '',
      updatedAt: (json['updatedAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'taskId': taskId,
      'epicName': epicName,
      'epicId': epicId,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'parentCommentId': parentCommentId,
      'content': content,
      'mentions': mentions.map((e) => e.toJson()).toList(),
      'replies': replies?.map((e) => e.toJson()).toList(),
      'reactions': reactions?.map((e) => e.toJson()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
