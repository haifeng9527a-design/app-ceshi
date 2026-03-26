const functions = require('firebase-functions');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();

// 新用户注册时自动设置 role: 'authenticated'，供 Supabase RLS 使用
exports.setSupabaseRoleOnCreate = functions.auth.user().onCreate(async (user) => {
  await admin.auth().setCustomUserClaims(user.uid, { role: 'authenticated' });
});
