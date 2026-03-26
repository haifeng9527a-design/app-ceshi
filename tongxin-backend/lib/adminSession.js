const crypto = require('crypto');

const DEFAULT_SESSION_TTL_HOURS = 12;

function getSessionSecret() {
  return String(process.env.ADMIN_SESSION_SECRET || process.env.ADMIN_API_KEY || '').trim();
}

function base64UrlEncode(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function base64UrlDecode(input) {
  const normalized = String(input || '')
    .replace(/-/g, '+')
    .replace(/_/g, '/');
  const pad = normalized.length % 4 === 0 ? '' : '='.repeat(4 - (normalized.length % 4));
  return Buffer.from(normalized + pad, 'base64').toString('utf8');
}

function signPayload(payloadText) {
  const secret = getSessionSecret();
  if (!secret) {
    throw new Error('Missing ADMIN_SESSION_SECRET or ADMIN_API_KEY');
  }
  return base64UrlEncode(
    crypto.createHmac('sha256', secret).update(payloadText).digest(),
  );
}

function createAdminSession({ adminId, username }) {
  const ttlHours = Math.max(1, parseInt(process.env.ADMIN_SESSION_TTL_HOURS || String(DEFAULT_SESSION_TTL_HOURS), 10) || DEFAULT_SESSION_TTL_HOURS);
  const now = Date.now();
  const payload = {
    sub: String(adminId || '').trim(),
    username: String(username || '').trim(),
    iat: now,
    exp: now + ttlHours * 60 * 60 * 1000,
  };
  if (!payload.sub || !payload.username) {
    throw new Error('Missing admin session subject');
  }
  const payloadText = JSON.stringify(payload);
  return `${base64UrlEncode(payloadText)}.${signPayload(payloadText)}`;
}

function verifyAdminSessionToken(token) {
  if (!token || typeof token !== 'string' || !token.includes('.')) return null;
  const [encodedPayload, signature] = token.split('.', 2);
  if (!encodedPayload || !signature) return null;
  try {
    const payloadText = base64UrlDecode(encodedPayload);
    const expectedSignature = signPayload(payloadText);
    const actual = Buffer.from(signature);
    const expected = Buffer.from(expectedSignature);
    if (actual.length !== expected.length || !crypto.timingSafeEqual(actual, expected)) {
      return null;
    }
    const payload = JSON.parse(payloadText);
    if (!payload?.sub || !payload?.username || !payload?.exp) return null;
    if (Number(payload.exp) <= Date.now()) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

function extractAdminSessionToken(req) {
  return (req.headers['x-admin-session'] || '').toString().trim();
}

function attachAdminSession(req) {
  if (req.isAdminSession === true) {
    return req.adminSession || null;
  }
  const token = extractAdminSessionToken(req);
  if (!token) return null;
  const payload = verifyAdminSessionToken(token);
  if (!payload) return null;
  req.isAdminSession = true;
  req.adminSession = payload;
  req.adminUserId = payload.sub;
  req.adminUsername = payload.username;
  req.firebaseUid = `admin:${payload.sub}`;
  return payload;
}

function requireAdminSession(req, res, next) {
  const payload = attachAdminSession(req);
  if (!payload) {
    return res.status(401).json({ error: '缺少或无效的 x-admin-session' });
  }
  return next();
}

module.exports = {
  attachAdminSession,
  createAdminSession,
  requireAdminSession,
  verifyAdminSessionToken,
};
