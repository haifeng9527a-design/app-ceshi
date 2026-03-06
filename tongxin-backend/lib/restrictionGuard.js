/**
 * 用户限制守卫：
 * - banned_until / frozen_until
 * - restrict_login / restrict_send_message / restrict_add_friend / restrict_join_group / restrict_create_group
 */

function _toBool(v) {
  if (v === true || v === 1) return true;
  if (typeof v === 'string') return v.trim().toLowerCase() === 'true' || v.trim() === '1';
  return false;
}

function _inEffect(iso) {
  if (!iso || typeof iso !== 'string') return false;
  const dt = new Date(iso);
  if (Number.isNaN(dt.getTime())) return false;
  return dt.getTime() > Date.now();
}

async function getUserRestrictionRow(sb, userId) {
  if (!sb || !userId) return null;
  const { data, error } = await sb
    .from('user_profiles')
    .select('banned_until, frozen_until, restrict_login, restrict_send_message, restrict_add_friend, restrict_join_group, restrict_create_group')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) return null;
  return data || null;
}

function checkAction(row, action) {
  if (!row) return { allowed: true };
  if (_inEffect(row.banned_until)) return { allowed: false, reason: '账号已封禁' };
  if (_inEffect(row.frozen_until)) return { allowed: false, reason: '账号已冻结' };
  if (action === 'login' && _toBool(row.restrict_login)) return { allowed: false, reason: '账号已限制登录' };
  if (action === 'send_message' && _toBool(row.restrict_send_message)) return { allowed: false, reason: '账号已限制发消息' };
  if (action === 'add_friend' && _toBool(row.restrict_add_friend)) return { allowed: false, reason: '账号已限制加好友' };
  if (action === 'join_group' && _toBool(row.restrict_join_group)) return { allowed: false, reason: '账号已限制加群' };
  if (action === 'create_group' && _toBool(row.restrict_create_group)) return { allowed: false, reason: '账号已限制建群' };
  return { allowed: true };
}

async function assertActionAllowed(sb, userId, action) {
  const row = await getUserRestrictionRow(sb, userId);
  return checkAction(row, action);
}

module.exports = {
  getUserRestrictionRow,
  checkAction,
  assertActionAllowed,
};

