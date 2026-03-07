/**
 * 调用后端 API（需 App 注入 apiBaseUrl 和 authToken）
 * @param {string} path - API 路径，如 'api/users/me'
 * @param {RequestInit} [options] - fetch 选项
 * @returns {Promise<Response>}
 */
function teacherHubApi(path, options = {}) {
  const bridge = window.TeacherHub;
  if (!bridge?.apiBaseUrl || !bridge?.authToken) {
    return Promise.reject(new Error("未注入 apiBaseUrl 或 authToken，请通过 App WebView 打开"));
  }
  const url = path.startsWith("/") ? `${bridge.apiBaseUrl}${path}` : `${bridge.apiBaseUrl}/${path}`;
  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json",
    Authorization: `Bearer ${bridge.authToken}`,
    ...options.headers,
  };
  return fetch(url, { ...options, headers });
}

function render() {
  const status = document.getElementById("status");
  const raw = document.getElementById("raw");
  const user = document.getElementById("user");

  const bridge = window.TeacherHub || null;
  const currentUser =
    typeof window.getTeacherHubCurrentUser === "function"
      ? window.getTeacherHubCurrentUser()
      : bridge?.user ?? null;

  raw.textContent = JSON.stringify(bridge, null, 2) || "null";
  user.textContent = JSON.stringify(currentUser, null, 2) || "null";

  if (currentUser && currentUser.uid) {
    status.className = "hint ok";
    status.textContent = `已获取登录用户: ${currentUser.uid}`;
    if (bridge?.apiBaseUrl && bridge?.authToken) {
      status.textContent += " | 可调用 teacherHubApi(path) 请求后端";
    }
  } else {
    status.className = "hint warn";
    status.textContent = "未获取到登录用户。请确认通过 App WebView 打开。";
  }
}

// 暴露给页面使用
window.teacherHubApi = teacherHubApi;

window.addEventListener("TeacherHubReady", render);
document.addEventListener("DOMContentLoaded", render);
setTimeout(render, 300);
