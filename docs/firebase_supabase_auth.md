# Firebase 登录与 Supabase RLS 鉴权对接

本应用使用 **Firebase Auth** 登录，数据在 **Supabase**。钱包等 RLS 策略依赖 `auth.uid()`，因此需要让 Supabase 在请求时识别当前 Firebase 用户。

## 已做改动（App 端）

- **Supabase 初始化**（`lib/core/supabase_bootstrap.dart`）已传入 `accessToken` 回调：每次请求会带上当前用户的 **Firebase ID Token**。
- 这样 Supabase 会把 JWT 中的 `sub` 当作 `auth.uid()`（即 Firebase UID），RLS 即可按用户隔离数据。

## 你需要在 Supabase 与 Firebase 完成的配置

### 1. Supabase：启用 Firebase 第三方登录（具体步骤）

1. **打开 Supabase 控制台**
   - 打开 [Supabase Dashboard](https://supabase.com/dashboard)，登录后选中你的项目（teacher_hub 对应的项目）。

2. **进入第三方认证设置**
   - 左侧菜单点 **Authentication**（认证）。
   - 在 Authentication 子菜单或页签里找到 **Third-party Auth**（第三方认证），点进去。
   - 直达链接格式：`https://supabase.com/dashboard/project/<你的项目ID>/auth/third-party`

3. **添加 Firebase 集成**
   - 页面上会有「Add integration」或「添加集成」之类的按钮，点它。
   - 在支持的第三方列表里选择 **Firebase**。
   - 唯一必填项是 **Firebase Project ID**（Firebase 项目 ID）。

4. **获取并填入 Firebase Project ID**
   - 打开 [Firebase 控制台](https://console.firebase.google.com) → 选中你的项目（和 App 里 `google-services.json` 对应的那个）。
   - 点击左上角齿轮 **项目设置** → 在「常规」页里找到 **项目 ID**（一串英文/数字，例如 `my-app-12345`）。
   - 把这段 **项目 ID** 原样复制到 Supabase 的 Firebase 集成里，保存。

5. **保存后**
   - Supabase 会校验请求头里的 Firebase ID Token（App 已通过 `accessToken` 自动带上），并据此设置 `auth.uid()`，RLS 即可按用户生效。

**说明**：若界面没有「Third-party Auth」入口，请确认 Supabase 项目版本/区域是否支持；也可在 [Supabase 官方文档](https://supabase.com/docs/guides/auth/third-party/firebase-auth) 查看最新截图与入口名称。

### 2. Firebase：为用户设置 `role: 'authenticated'`

Supabase 根据 JWT 里的 **role** 决定使用 `authenticated` 还是 `anon`，必须给所有用户（包括今后新注册的）加上 `role: 'authenticated'`。按下面两步做即可。

---

#### 步骤 2.1：给「现有用户」批量加上 role（跑一次脚本）

1. 在电脑上建一个空目录，例如 `firebase-claim-script`，进入该目录。
2. 执行：
   ```bash
   npm init -y
   npm install firebase-admin
   ```
3. 获取**服务账号密钥**：Firebase 控制台 → 项目设置 → 服务账号 → 选择「Firebase Admin SDK」→ 点击「生成新的私钥」，下载 JSON 文件，保存到该目录并重命名为 `serviceAccountKey.json`（或记住你起的名字）。
4. 在同一目录新建文件 `set-role-claim.js`，内容如下（若密钥文件名不是 `serviceAccountKey.json`，改掉第 3 行的路径）：
   ```javascript
   'use strict';
   const admin = require('firebase-admin');
   const path = require('path');

   admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, 'serviceAccountKey.json'))) });
   const auth = admin.auth();

   async function setRoleForAll() {
     let nextPageToken;
     let total = 0;
     do {
       const list = await auth.listUsers(1000, nextPageToken);
       nextPageToken = list.pageToken;
       await Promise.all(list.users.map(async (u) => {
         await auth.setCustomUserClaims(u.uid, { role: 'authenticated' });
         total++;
         console.log('OK', u.uid);
       }));
     } while (nextPageToken);
     console.log('Done. Total users set:', total);
   }

   setRoleForAll().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
   ```
5. 在该目录执行：
   ```bash
   node set-role-claim.js
   ```
   看到 `Done. Total users set: N` 即表示现有用户都已加上 `role: 'authenticated'`。

---

#### 步骤 2.2：让「新用户」自动带上 role（部署一个 Cloud Function）

1. 在项目根目录（与 `app` 同级）初始化 Firebase Functions（若还没有）：
   ```bash
   cd d:\teacher_hub
   firebase init functions
   ```
   选择 TypeScript 或 JavaScript，按提示完成。若已存在 `functions` 目录则跳过。
2. 进入 `functions` 目录，安装依赖（若用 TypeScript）：
   ```bash
   cd functions
   npm install
   ```
3. 打开 `functions/src/index.ts`（或 `functions/index.js`），在文件末尾**新增**下面这段（不要删掉原有代码）：
   ```javascript
   // 新用户注册时自动设置 role: 'authenticated'，供 Supabase 使用
   const functions = require('firebase-functions');
   const admin = require('firebase-admin');
   if (!admin.apps.length) admin.initializeApp();

   exports.setSupabaseRoleOnCreate = functions.auth.user().onCreate(async (user) => {
     await admin.auth().setCustomUserClaims(user.uid, { role: 'authenticated' });
   });
   ```
   若你用的是 TypeScript（`index.ts`），等价写法：
   ```typescript
   import * as functions from 'firebase-functions';
   import * as admin from 'firebase-admin';
   if (!admin.apps.length) admin.initializeApp();

   export const setSupabaseRoleOnCreate = functions.auth.user().onCreate(async (user) => {
     await admin.auth().setCustomUserClaims(user.uid, { role: 'authenticated' });
   });
   ```
4. 部署云函数：
   ```bash
   firebase deploy --only functions
   ```
5. 之后**新注册**的用户会自动带有 `role: 'authenticated'`。已用步骤 2.1 跑过脚本的**老用户**无需再操作。

---

#### 步骤 2.3：App 里刷新一次 Token（老用户必做一次）

已存在的用户在你跑完 2.1 之后，要**重新拿一次 ID Token** 才会带上 `role`。让用户**退出登录再重新登录一次**即可；或在登录成功后调用一次 `FirebaseAuth.instance.currentUser?.getIdToken(true)` 强制刷新（你当前 Supabase 的 `accessToken` 回调下次请求时会自动用到新 token）。

完成 2.1、2.2、2.3 后，钱包、好友申请等依赖 `auth.uid()` 的 RLS 会按当前 Firebase 用户正确生效。

### 3. 若「发布策略」报错 invalid input syntax for type uuid

Supabase 里 `auth.uid()` 的返回类型是 **uuid**。使用 Firebase JWT 时，JWT 的 `sub` 是 Firebase UID（如 `OFxSf3otmqaEJo7vvDwgJNORfbG2`），不是合法 UUID，在 RLS 里一旦调用 `auth.uid()` 就会触发类型转换报错。

**处理方式**：对存 Firebase UID 的表（如 `trade_strategies`、`trade_records` 等），RLS 不要用 `auth.uid()::text`，改用 **`(auth.jwt()->>'sub')`** 直接从 JWT 取 `sub` 文本。

在 Supabase SQL Editor 中**一次性执行**项目里的 `docs/fix_rls_use_jwt_sub.sql`，会把这些表的策略改为用 `auth.jwt()->>'sub'`，执行后再在 App 里重试「发布策略」。

## 参考

- [Supabase: Use Firebase Auth](https://supabase.com/docs/guides/auth/third-party/firebase-auth)
- [Firebase: Custom claims](https://firebase.google.com/docs/auth/admin/custom-claims)
