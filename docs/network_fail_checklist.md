# 全部“网络失败”排查清单

当两台手机都连 WiFi 但发消息、加好友、退群等全部失败时，按下面顺序检查。

---

## 1. Supabase 项目是否暂停（最常见）

免费版 Supabase 项目**一周无访问会自动暂停**。

- 打开 [Supabase Dashboard](https://supabase.com/dashboard)，登录后看你的项目。
- 若项目显示 **Paused** 或「已暂停」，点 **Restore project** 恢复。
- 恢复后等 1～2 分钟再在 APP 里重试。

---

## 2. 用电脑浏览器测同一网络

在**连同一 WiFi 的电脑**上：

- 打开浏览器，访问：  
  `https://你的SUPABASE项目ID.supabase.co/rest/v1/`  
  （替换成你 .env 里的 `SUPABASE_URL` 里的域名）
- 若打不开、一直转圈或证书错误，说明当前 WiFi/网络访问不了 Supabase，需换网或检查路由器/防火墙。

---

## 3. 看 APP 真实报错（推荐）

已在代码里加日志：每次出现「网络异常 / 发送失败 / 退出失败」等时，会把**真实异常**打到控制台。

**用数据线连手机 + 电脑，在项目里跑：**

```bash
cd app
flutter run
```

然后在 APP 里故意触发一次失败（发消息、退群等），在终端或 Android Studio 的 **Logcat** 里搜：

- `[Supabase]`：看 Supabase 是否初始化成功（init OK / init failed）
- `[NetworkError]`：看具体错误，例如：
  - `401` / `JWT` / `expired` → 登录过期，需重新登录
  - `403` / `policy` / `RLS` → 权限/策略问题
  - `SocketException` / `timeout` → 真网络或连不上服务器
  - `column "last_sender_id" does not exist` → 数据库触发器/表结构问题

根据这里的具体错误再往下查。

---

## 4. 确认 .env 打进安装包（Release 包）

若你装的是 **release APK**（自己打的 app-release.apk），要确认构建时能读到 Supabase 配置：

- 若用 **flutter_dotenv + assets: .env**：release 会把 `app/.env` 打进包，一般没问题。
- 若构建时用的是 **--dart-define** 而不是 .env，要确保当时传了：
  - `SUPABASE_URL=...`
  - `SUPABASE_ANON_KEY=...`

否则 APP 里 Supabase 会 init 失败，所有请求都像「网络失败」。  
用「3. 看 APP 真实报错」跑一次，看是否有 `[Supabase] init skipped` 或 `init failed`。

---

## 5. Firebase 登录是否正常

APP 用 Firebase 的 ID Token 访问 Supabase。若 Firebase 没登录或 token 失效，Supabase 请求会 401。

- 在 APP 里退出登录，再重新登录一次，然后重试发消息/退群。
- 若日志里出现 401/JWT expired，优先重新登录。

---

## 6. Supabase 表/触发器是否改坏

若你刚执行过和 `chat_messages` / `chat_conversations` 相关的 SQL（例如触发器）：

- 若触发器里有不存在的列（如 `last_sender_id`），**插入消息会报错**，APP 上就表现为发送失败。
- 在 Supabase Dashboard → **Table Editor** 里随便打开 `chat_messages`，试着手动插一条记录，看是否报错。
- 或在 **SQL Editor** 里执行一条简单插入，看报错信息是否和「列不存在」或「触发器错误」有关。若有，需要把触发器或表结构改回一致。

---

## 小结

| 现象           | 优先检查                           |
|----------------|------------------------------------|
| 两台手机都失败 | Supabase 是否暂停、同一 WiFi 是否能访问 Supabase |
| 一直提示网络异常 | 用 `flutter run` + 搜 `[NetworkError]`、`[Supabase]` 看真实错误 |
| 发消息/退群失败 | Supabase 暂停、触发器报错、401 需重新登录 |

按 1 → 2 → 3 做一遍，大多能定位是「项目暂停」「网络不通」还是「鉴权/表结构」问题。
