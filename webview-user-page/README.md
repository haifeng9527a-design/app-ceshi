# webview-user-page

用于给 Flutter App 的 WebView 调用，展示 App 注入的当前登录用户信息。

## Render 部署（静态站点）

1. 登录 [Render Dashboard](https://dashboard.render.com)
2. 点击 **New** → **Static Site**
3. 连接 GitHub 仓库 `haifeng9527a-design/webview-user-page`
4. 配置：
   - **Name**: `webview-user-page`（或自定义）
   - **Branch**: `main`
   - **Build Command**: `npm install && npm run build`
   - **Publish Directory**: `dist`
5. 点击 **Create Static Site**，等待部署完成
6. 部署成功后获得 URL，如 `https://webview-user-page.onrender.com`
7. 在 `app_config` 或 `tongxin-frontend/.env` 中配置：
   ```env
   WEBVIEW_USER_PAGE_URL=https://webview-user-page.onrender.com
   ```

## 启动

```bash
npm install
npm run dev
```

默认地址：`http://localhost:5174`

## Flutter 端配置

在 `tongxin-frontend/.env` 中配置：

```env
WEBVIEW_USER_PAGE_URL=http://你的电脑局域网IP:5174
```

示例：

```env
WEBVIEW_USER_PAGE_URL=http://192.168.1.100:5174
```

> 真机调试时，不能使用 `localhost`，需要使用电脑的局域网 IP。

## Web 页面可用数据

App WebView 注入：

- `window.TeacherHub` — 包含 `user`、`app`、`apiBaseUrl`、`authToken`
- `window.getTeacherHubCurrentUser()` — 获取当前用户
- `TeacherHubReady` 事件 — 注入完成时触发

## 调用后端 API

当 App 注入 `apiBaseUrl` 和 `authToken` 后，页面可使用 `teacherHubApi(path)` 调用需鉴权的接口：

```javascript
// GET 请求
const resp = await teacherHubApi("api/users/me");
const data = await resp.json();

// POST 请求
const resp = await teacherHubApi("api/xxx", {
  method: "POST",
  body: JSON.stringify({ key: "value" }),
});
```

Token 约 1 小时过期，过期后需用户重新打开此页面。
