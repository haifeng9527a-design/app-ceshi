/**
 * Firebase ID Token 鉴权中间件
 * 从 Authorization: Bearer <token> 解析并验证，将 uid 写入 req.firebaseUid
 * 环境变量：GOOGLE_APPLICATION_CREDENTIALS（服务账号 JSON 路径）或 FIREBASE_PROJECT_ID
 */
let admin = null;
let auth = null;
const supabaseClient = require('./supabaseClient');
const restrictionGuard = require('./restrictionGuard');
const restrictionCache = new Map();
const RESTRICTION_CACHE_MS = 30 * 1000;

function initFirebase() {
  if (admin) return auth != null;
  try {
    admin = require('firebase-admin');
    const jsonCred = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
    const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
    const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
    if (admin.apps.length === 0) {
      if (jsonCred) {
        // 部署到 Render 等云平台：服务账号 JSON 存环境变量，无需文件
        const serviceAccount = JSON.parse(jsonCred);
        admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
      } else if (credPath) {
        // 本地开发：从文件路径加载
        admin.initializeApp({ credential: admin.credential.applicationDefault() });
      } else if (projectId) {
        admin.initializeApp({ projectId });
      } else {
        console.warn('[auth] Firebase Admin 未配置：需 FIREBASE_SERVICE_ACCOUNT_JSON、GOOGLE_APPLICATION_CREDENTIALS 或 FIREBASE_PROJECT_ID');
        return false;
      }
    }
    auth = admin.auth();
    return true;
  } catch (e) {
    console.warn('[auth] Firebase Admin 初始化失败:', e.message);
    return false;
  }
}

function isAuthConfigured() {
  return initFirebase() && auth != null;
}

/**
 * 可选鉴权：有 token 则验证并设置 req.firebaseUid，无 token 则 req.firebaseUid = null
 */
async function optionalAuth(req, res, next) {
  req.firebaseUid = null;
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) return next();
  const token = authHeader.slice(7).trim();
  if (!token) return next();
  if (!isAuthConfigured()) return next();
  try {
    const decoded = await auth.verifyIdToken(token);
    req.firebaseUid = decoded.uid;
  } catch (_) {
    // token 无效或过期，保持 firebaseUid = null
  }
  next();
}

/**
 * 必须鉴权：无有效 token 则 401
 */
async function requireAuth(req, res, next) {
  const adminKey = process.env.ADMIN_API_KEY?.trim();
  const requestAdminKey = (req.headers['x-admin-key'] || '').toString().trim();
  if (adminKey && requestAdminKey && requestAdminKey === adminKey) {
    req.firebaseUid = 'admin_api_key';
    req.isAdminByKey = true;
    return next();
  }
  if (!isAuthConfigured()) {
    return res.status(503).json({ error: '鉴权服务未配置' });
  }
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: '缺少 Authorization: Bearer <token>' });
  }
  const token = authHeader.slice(7).trim();
  if (!token) {
    return res.status(401).json({ error: 'Token 为空' });
  }
  try {
    const decoded = await auth.verifyIdToken(token);
    req.firebaseUid = decoded.uid;
    const sb = supabaseClient.getClient();
    if (sb && req.firebaseUid) {
      const now = Date.now();
      const cached = restrictionCache.get(req.firebaseUid);
      let row = null;
      if (cached && now - cached.at < RESTRICTION_CACHE_MS) {
        row = cached.row;
      } else {
        row = await restrictionGuard.getUserRestrictionRow(sb, req.firebaseUid);
        restrictionCache.set(req.firebaseUid, { at: now, row });
      }
      const loginGate = restrictionGuard.checkAction(row, 'login');
      if (!loginGate.allowed) {
        return res.status(403).json({ error: loginGate.reason || '账号已限制登录' });
      }
    }
    next();
  } catch (e) {
    return res.status(401).json({ error: 'Token 无效或已过期' });
  }
}

module.exports = { optionalAuth, requireAuth, isAuthConfigured };
