class FriendProfile {
  const FriendProfile({
    required this.userId,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    this.status = 'offline',
    this.shortId,
    this.level = 0,
    this.roleLabel,
    this.lastOnlineAt,
  });

  final String userId;
  final String displayName;
  /// 仅用于搜索与后端，不在列表中展示
  final String email;
  final String? avatarUrl;
  final String status;
  /// 账号ID，用于列表中展示
  final String? shortId;
  final int level;
  /// 认证状态展示文案，如「交易员」「普通用户」
  final String? roleLabel;
  /// 最后上线时间（退出 APP/后台/关闭聊天时更新），好友在聊天窗口可见
  final DateTime? lastOnlineAt;
}

class FriendRequestItem {
  const FriendRequestItem({
    required this.requestId,
    required this.requesterId,
    required this.requesterName,
    required this.requesterEmail,
    this.requesterAvatar,
    this.requesterShortId,
    this.status = 'pending',
    this.createdAt,
    this.isOutgoing = false,
    this.receiverId,
    this.receiverName,
    this.receiverAvatar,
    this.receiverShortId,
  });

  final String requestId;
  final String requesterId;
  final String requesterName;
  final String requesterEmail;
  final String? requesterAvatar;
  /// 申请者账号ID，用于展示（不展示邮箱保护隐私）
  final String? requesterShortId;
  /// pending | accepted | rejected
  final String status;
  /// 申请/处理时间，用于系统消息列表排序与展示
  final DateTime? createdAt;
  /// true = 我发出的申请（对方为 receiver）；false = 我收到的申请（对方为 requester）
  final bool isOutgoing;
  /// 仅当 isOutgoing 时有意义：接收方（对方）信息，用于展示
  final String? receiverId;
  final String? receiverName;
  final String? receiverAvatar;
  final String? receiverShortId;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';

  /// 列表展示用的对方头像 URL（发出的申请用 receiver，收到的用 requester）
  String? get otherAvatar => isOutgoing ? receiverAvatar : requesterAvatar;
  /// 列表展示用的对方昵称
  String get otherDisplayName => isOutgoing ? (receiverName ?? '用户') : requesterName;
  /// 列表展示用的对方账号 ID
  String? get otherShortId => isOutgoing ? receiverShortId : requesterShortId;

  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'requesterEmail': requesterEmail,
      'requesterAvatar': requesterAvatar,
      'requesterShortId': requesterShortId,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'isOutgoing': isOutgoing,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverAvatar': receiverAvatar,
      'receiverShortId': receiverShortId,
    };
  }

  factory FriendRequestItem.fromJson(Map<String, dynamic> json) {
    return FriendRequestItem(
      requestId: json['requestId'] as String? ?? '',
      requesterId: json['requesterId'] as String? ?? '',
      requesterName: json['requesterName'] as String? ?? '',
      requesterEmail: json['requesterEmail'] as String? ?? '',
      requesterAvatar: json['requesterAvatar'] as String?,
      requesterShortId: json['requesterShortId'] as String?,
      status: json['status'] as String? ?? 'pending',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      isOutgoing: json['isOutgoing'] as bool? ?? false,
      receiverId: json['receiverId'] as String?,
      receiverName: json['receiverName'] as String?,
      receiverAvatar: json['receiverAvatar'] as String?,
      receiverShortId: json['receiverShortId'] as String?,
    );
  }
}
