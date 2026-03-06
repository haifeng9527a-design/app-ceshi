# webview-user-page

用于给 Flutter App 的 WebView 调用，展示 App 注入的当前登录用户信息。

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

- `window.TeacherHub`
- `window.getTeacherHubCurrentUser()`
- `TeacherHubReady` 事件

页面可直接读取并展示当前用户信息。
