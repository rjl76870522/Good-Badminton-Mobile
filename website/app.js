const root = document.documentElement;
const progress = document.querySelector(".scroll-progress");
const parallaxItems = [...document.querySelectorAll("[data-parallax]")];
const sceneMedia = [...document.querySelectorAll(".scroll-scene .scene-media")];

function updateScrollEffects() {
  const scrollTop = window.scrollY;
  const maxScroll = root.scrollHeight - window.innerHeight;
  if (progress) progress.style.transform = `scaleX(${maxScroll > 0 ? scrollTop / maxScroll : 0})`;

  parallaxItems.forEach((item) => {
    const scene = item.closest("section");
    const rect = scene.getBoundingClientRect();
    const amount = Number(item.dataset.parallax || 0);
    item.style.transform = `translate3d(0, ${(window.innerHeight - rect.top) * amount}px, 0)`;
  });

  sceneMedia.forEach((media) => {
    const rect = media.parentElement.getBoundingClientRect();
    const progressInScene = Math.max(0, Math.min(1, -rect.top / Math.max(1, rect.height - window.innerHeight)));
    media.style.transform = `scale(${1.04 + progressInScene * 0.1}) translate3d(0, ${progressInScene * 2.5}%, 0)`;
  });
}

const revealObserver = new IntersectionObserver(
  (entries) => entries.forEach((entry) => entry.target.classList.toggle("is-visible", entry.isIntersecting)),
  { threshold: 0.16 },
);

document.querySelectorAll(".reveal").forEach((element) => revealObserver.observe(element));

let ticking = false;
window.addEventListener("scroll", () => {
  if (ticking) return;
  ticking = true;
  requestAnimationFrame(() => {
    updateScrollEffects();
    ticking = false;
  });
}, { passive: true });

updateScrollEffects();
