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
  } else {
    status.className = "hint warn";
    status.textContent = "未获取到登录用户。请确认通过 App WebView 打开。";
  }
}

window.addEventListener("TeacherHubReady", render);
document.addEventListener("DOMContentLoaded", render);
setTimeout(render, 300);
