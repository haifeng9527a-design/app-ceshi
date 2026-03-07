# 后端配置指南

## 一、Firebase Admin（鉴权）

用于验证前端传来的 Firebase ID Token，聊天、好友等接口依赖此配置。

### 步骤

1. 打开 [Firebase 控制台](https://console.firebase.google.com/)
2. 选择你的项目（与前端 Firebase 配置同一项目）
3. 点击 **项目设置**（齿轮图标）→ **服务账号**
4. 点击 **生成新私钥** → 确认
5. 下载的 JSON 文件保存到 `tongxin-backend/` 目录，命名为 `serviceAccountKey.json`
6. 在 `tongxin-backend/.env` 中添加：
   ```
   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
   ```

> 注意：`serviceAccountKey.json` 含敏感信息，已加入 .gitignore，切勿提交到版本库。

### 云部署（Render / Railway / 等）

云平台通常**不包含**本地文件，需将服务账号 JSON 存为环境变量：

1. 打开 `serviceAccountKey.json`，复制**完整内容**（单行或格式化均可）
2. 在 Render 等平台的环境变量中添加：
   - **Key**: `FIREBASE_SERVICE_ACCOUNT_JSON`
   - **Value**: 粘贴完整 JSON（注意不要有多余换行或引号包裹）

Render 示例：Dashboard → 你的 Service → Environment → Add Environment Variable

---

## 二、Supabase Service Role Key

后端需使用 **service_role** 密钥访问数据库，绕过 RLS，否则聊天等表查询可能被拦截。

### 步骤

1. 打开 [Supabase 控制台](https://supabase.com/dashboard/)
2. 选择项目 `theqizksqjrylsnrrrhx`
3. 进入 **Settings** → **API**
4. 在 **Project API keys** 中找到 **service_role**（Secret）
5. 点击 **Reveal** 复制密钥
6. 在 `tongxin-backend/.env` 中添加：
   ```
   SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.你的service_role密钥
   ```

---

## 三、完整 .env 示例

**本地开发：**
```env
PORT=3000
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=你的service_role密钥
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
```

**云部署（Render 等）：** 用环境变量 `FIREBASE_SERVICE_ACCOUNT_JSON` 替代 `GOOGLE_APPLICATION_CREDENTIALS`，值为 serviceAccountKey.json 的完整 JSON 字符串。

---

## 四、配置完成后

重启后端：

```powershell
cd d:\teacher_hub\tongxin-backend
npm start
```

启动成功且无 `[auth] Firebase Admin 未配置` 警告即表示配置正确。
