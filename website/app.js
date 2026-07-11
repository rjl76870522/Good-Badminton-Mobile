const statusText = document.getElementById("api-status");
const statusDot = document.getElementById("api-dot");
const backendDetail = document.getElementById("backend-detail");

async function checkApi() {
  if (!statusText || !statusDot) return;
  try {
    const response = await fetch("https://api.audacity6441.kdns.fr/api/health", {
      cache: "no-store",
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    statusText.textContent = data.ok ? "服务器在线" : "服务器状态异常";
    statusDot.classList.toggle("ok", Boolean(data.ok));
    if (backendDetail) {
      backendDetail.textContent = data.ok ? "在线，Cloudflare 公网入口可用" : "状态异常";
    }
  } catch (error) {
    statusText.textContent = "服务器暂时不可达";
    statusDot.classList.remove("ok");
    if (backendDetail) backendDetail.textContent = "暂时不可达，请检查 Tunnel 或后端服务";
  }
}

checkApi();
