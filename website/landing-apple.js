const observer = new IntersectionObserver(
  (entries) => entries.forEach((entry) => entry.target.classList.toggle("visible", entry.isIntersecting)),
  { threshold: 0.15 },
);
document.querySelectorAll(".reveal").forEach((element) => observer.observe(element));
document.querySelector(".hero .reveal")?.classList.add("visible");

const serverStatus = document.querySelector("#server-status");
if (serverStatus) {
  fetch("https://api.audacity6441.kdns.fr/api/health", { cache: "no-store" })
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.json();
    })
    .then((data) => {
      const online = Boolean(data.ok);
      serverStatus.classList.toggle("offline", !online);
      serverStatus.querySelector("span").textContent = online ? "分析服务器在线" : "分析服务器状态异常";
    })
    .catch(() => {
      serverStatus.classList.add("offline");
      serverStatus.querySelector("span").textContent = "分析服务器暂时无法连接";
    });
}
