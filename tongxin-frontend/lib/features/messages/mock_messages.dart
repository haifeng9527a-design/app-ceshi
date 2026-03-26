import 'message_models.dart';

const List<Conversation> mockConversations = [
  Conversation(
    id: 'c1',
    title: '周远',
    subtitle: '量化策略教练',
    lastMessage: '今晚 8 点直播复盘，记得参加。',
    lastTime: null,
    peerId: 'u1',
    avatarText: '周',
    unreadCount: 2,
  ),
  Conversation(
    id: 'c2',
    title: '高阶研修群',
    subtitle: '群聊 · 128 人',
    lastMessage: '交易员已发布今日策略解读。',
    lastTime: null,
    avatarText: '研',
    unreadCount: 5,
    isGroup: true,
  ),
  Conversation(
    id: 'c3',
    title: '客服助手',
    subtitle: '系统通知',
    lastMessage: '欢迎加入金融培训机构。',
    lastTime: null,
    peerId: 'system',
    avatarText: '客',
  ),
];

final Map<String, List<ChatMessage>> mockMessages = {
  'c1': [
    ChatMessage(
      id: 'm1',
      senderId: 'u1',
      senderName: '周远',
      content: '今天先复盘早盘情绪，晚上再看策略。',
      messageType: 'text',
      time: DateTime(2025, 1, 1, 12, 35),
      isMine: false,
    ),
    ChatMessage(
      id: 'm2',
      senderId: 'me',
      senderName: '我',
      content: '收到，晚上一定参加。',
      messageType: 'text',
      time: DateTime(2025, 1, 1, 12, 36),
      isMine: true,
    ),
    ChatMessage(
      id: 'm3',
      senderId: 'u1',
      senderName: '周远',
      content: '记得先把昨天的笔记整理一下。',
      messageType: 'text',
      time: DateTime(2025, 1, 1, 12, 40),
      isMine: false,
    ),
  ],
  'c2': [
    ChatMessage(
      id: 'm4',
      senderId: 'u2',
      senderName: '群主',
      content: '欢迎新同学加入，请先查看群公告。',
      messageType: 'text',
      time: DateTime(2025, 1, 1, 9, 10),
      isMine: false,
    ),
    ChatMessage(
      id: 'm5',
      senderId: 'me',
      senderName: '我',
      content: '收到，已看公告。',
      messageType: 'text',
      time: DateTime(2025, 1, 1, 9, 12),
      isMine: true,
    ),
  ],
  'c3': [
    ChatMessage(
      id: 'm6',
      senderId: 'system',
      senderName: '系统',
      content: '你已完成注册，开始你的学习之旅。',
      messageType: 'text',
      time: DateTime(2025, 1, 1, 9, 0),
      isMine: false,
    ),
  ],
};
