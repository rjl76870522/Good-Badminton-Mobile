const observer = new IntersectionObserver(
  (entries) => entries.forEach((entry) => entry.target.classList.toggle("visible", entry.isIntersecting)),
  { threshold: 0.15 },
);
document.querySelectorAll(".reveal").forEach((element) => observer.observe(element));
document.querySelector(".hero .reveal")?.classList.add("visible");
