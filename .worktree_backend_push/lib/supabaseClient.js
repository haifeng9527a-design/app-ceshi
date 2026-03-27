/**
 * 通用 Supabase 客户端（Service Role），用于 backend 代理所有数据库操作
 * 环境变量：SUPABASE_URL、SUPABASE_SERVICE_ROLE_KEY（或 SUPABASE_ANON_KEY）
 */
const { createClient } = require('@supabase/supabase-js');

let _client = null;

function getClient() {
  if (_client) return _client;
  const url = process.env.SUPABASE_URL?.trim();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() || process.env.SUPABASE_ANON_KEY?.trim();
  if (!url || !key) return null;
  _client = createClient(url, key);
  return _client;
}

function isConfigured() {
  return !!(process.env.SUPABASE_URL?.trim() && (process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() || process.env.SUPABASE_ANON_KEY?.trim()));
}

module.exports = { getClient, isConfigured };
