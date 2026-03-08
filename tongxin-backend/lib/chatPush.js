/**
 * 聊天消息推送：消息入库后调用 send_push，为会话内除发送者外的成员发送离线通知。
 * send_push 内部会自动在 FCM / 个推之间选择合适通道。
 */
async function triggerChatMessagePush(sb, record) {
  const conversationId = record?.conversation_id;
  const senderId = record?.sender_id;
  const senderName = String(record?.sender_name || '').trim() || '新消息';
  const messageType = String(record?.message_type || 'text');
  const content = String(record?.content || '').trim();
  const body = content.length > 100 ? `${content.slice(0, 100)}...` : (content || '发来一条消息');

  if (!sb || !conversationId || !senderId) return { ok: false, pushed: 0, reason: 'missing conversation_id or sender_id' };

  const { data: members, error: membersError } = await sb
    .from('chat_members')
    .select('user_id, role')
    .eq('conversation_id', conversationId)
    .neq('user_id', senderId);

  if (membersError || !members || members.length === 0) {
    return { ok: true, pushed: 0, reason: membersError?.message || 'no receivers' };
  }

  let receiverIds = members
    .map((m) => m.user_id)
    .filter((id) => typeof id === 'string' && id && id !== senderId);

  if (messageType === 'system_leave') {
    receiverIds = members
      .filter((m) => m.role === 'owner' || m.role === 'admin')
      .map((m) => m.user_id)
      .filter((id) => typeof id === 'string' && id && id !== senderId);
  }

  if (receiverIds.length === 0) {
    return { ok: true, pushed: 0, reason: 'no receivers after filtering' };
  }

  let pushed = 0;
  for (const receiverId of receiverIds) {
    try {
      const { error } = await sb.functions.invoke('send_push', {
        body: {
          receiverId,
          senderId,
          title: senderName,
          body,
          conversationId: String(conversationId),
          messageType,
        },
      });
      if (!error) pushed += 1;
    } catch (_) {
      // 尽量继续发给其他成员，单个失败不影响整体。
    }
  }

  return { ok: true, pushed, receivers: receiverIds.length };
}

module.exports = { triggerChatMessagePush };
