const header = document.querySelector(".header");
const menuButton = document.querySelector(".menu-button");
const menuPanel = document.querySelector(".menu-panel");
const panels = document.querySelectorAll(".panel");

function closeMenu() {
  menuButton.classList.remove("open");
  menuPanel.classList.remove("open");
  menuButton.setAttribute("aria-expanded", "false");
}

menuButton.addEventListener("click", () => {
  const open = !menuButton.classList.contains("open");
  menuButton.classList.toggle("open", open);
  menuPanel.classList.toggle("open", open);
  menuButton.setAttribute("aria-expanded", String(open));
});

menuPanel.querySelectorAll("a").forEach((link) => link.addEventListener("click", closeMenu));
window.addEventListener("scroll", () => header.classList.toggle("scrolled", window.scrollY > 30), { passive: true });

const observer = new IntersectionObserver(
  (entries) => entries.forEach((entry) => entry.target.classList.toggle("active", entry.isIntersecting)),
  { threshold: 0.38 },
);
panels.forEach((panel) => observer.observe(panel));
panels[0]?.classList.add("active");
