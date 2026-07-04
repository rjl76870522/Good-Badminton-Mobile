const apiBase = window.location.origin;
const state = {
  userId: getStoredUserId(),
  selectedFile: null,
  currentTaskId: null,
  pollTimer: null,
};

const els = {
  healthDot: document.querySelector("#healthDot"),
  healthText: document.querySelector("#healthText"),
  baseUrlText: document.querySelector("#baseUrlText"),
  userIdInput: document.querySelector("#userIdInput"),
  resetUserButton: document.querySelector("#resetUserButton"),
  tabs: document.querySelectorAll(".tab"),
  views: document.querySelectorAll(".view"),
  uploadForm: document.querySelector("#uploadForm"),
  videoInput: document.querySelector("#videoInput"),
  cornersJsonInput: document.querySelector("#cornersJsonInput"),
  fileName: document.querySelector("#fileName"),
  progressWrap: document.querySelector("#progressWrap"),
  taskStage: document.querySelector("#taskStage"),
  taskPercent: document.querySelector("#taskPercent"),
  progressFill: document.querySelector("#progressFill"),
  messageBox: document.querySelector("#messageBox"),
  refreshHistoryButton: document.querySelector("#refreshHistoryButton"),
  loadDemoButton: document.querySelector("#loadDemoButton"),
  historyList: document.querySelector("#historyList"),
  reportSubtitle: document.querySelector("#reportSubtitle"),
  summaryGrid: document.querySelector("#summaryGrid"),
  adviceList: document.querySelector("#adviceList"),
  highlightVideo: document.querySelector("#highlightVideo"),
  analysisVideo: document.querySelector("#analysisVideo"),
  heatmapImage: document.querySelector("#heatmapImage"),
  trajectoryImage: document.querySelector("#trajectoryImage"),
  highlightEmpty: document.querySelector("#highlightEmpty"),
  analysisEmpty: document.querySelector("#analysisEmpty"),
  heatmapEmpty: document.querySelector("#heatmapEmpty"),
  trajectoryEmpty: document.querySelector("#trajectoryEmpty"),
  highlightLink: document.querySelector("#highlightLink"),
  analysisVideoLink: document.querySelector("#analysisVideoLink"),
  heatmapLink: document.querySelector("#heatmapLink"),
  trajectoryLink: document.querySelector("#trajectoryLink"),
};

init();

function init() {
  els.userIdInput.value = state.userId;
  els.baseUrlText.textContent = apiBase;
  bindEvents();
  checkHealth();
  loadHistory();
}

function bindEvents() {
  els.tabs.forEach((tab) => {
    tab.addEventListener("click", () => switchView(tab.dataset.view));
  });

  els.userIdInput.addEventListener("change", () => {
    state.userId = sanitizeUserId(els.userIdInput.value);
    els.userIdInput.value = state.userId;
    localStorage.setItem("good_badminton_user_id", state.userId);
    loadHistory();
  });

  els.resetUserButton.addEventListener("click", () => {
    state.userId = createGuestId();
    els.userIdInput.value = state.userId;
    localStorage.setItem("good_badminton_user_id", state.userId);
    loadHistory();
  });

  els.videoInput.addEventListener("change", () => {
    state.selectedFile = els.videoInput.files[0] || null;
    els.fileName.textContent = state.selectedFile ? state.selectedFile.name : "选择或拖入视频";
  });

  ["dragenter", "dragover"].forEach((eventName) => {
    els.uploadForm.addEventListener(eventName, (event) => {
      event.preventDefault();
      els.uploadForm.classList.add("is-dragging");
    });
  });

  ["dragleave", "drop"].forEach((eventName) => {
    els.uploadForm.addEventListener(eventName, (event) => {
      event.preventDefault();
      els.uploadForm.classList.remove("is-dragging");
    });
  });

  els.uploadForm.addEventListener("drop", (event) => {
    const file = event.dataTransfer.files[0];
    if (!file) return;
    state.selectedFile = file;
    els.fileName.textContent = file.name;
  });

  els.uploadForm.addEventListener("submit", uploadVideo);
  els.refreshHistoryButton.addEventListener("click", loadHistory);
  els.loadDemoButton.addEventListener("click", loadDemoSample);
}

async function checkHealth() {
  try {
    const data = await apiGet("/api/health");
    els.healthDot.classList.add("is-ok");
    els.healthDot.classList.remove("is-bad");
    els.healthText.textContent = data.ok ? "后端已连接" : "后端异常";
  } catch (error) {
    els.healthDot.classList.add("is-bad");
    els.healthText.textContent = "后端未连接";
    showMessage(error.message);
  }
}

async function uploadVideo(event) {
  event.preventDefault();
  clearMessage();

  const file = state.selectedFile || els.videoInput.files[0];
  if (!file) {
    showMessage("请先选择视频文件。");
    return;
  }

  let cornersJson = "";
  try {
    cornersJson = normalizeCornersJson(els.cornersJsonInput.value);
  } catch (error) {
    showMessage(error.message);
    return;
  }

  const form = new FormData();
  form.append("file", file);
  form.append("user_id", state.userId);
  form.append("language", "zh");
  form.append("pose_mode", "balanced");
  form.append("keep_audio", "true");
  if (cornersJson) {
    form.append("corners_json", cornersJson);
  }

  setProgress(0, "上传中");
  els.progressWrap.hidden = false;

  try {
    const upload = await apiRequest("/api/videos/upload", {
      method: "POST",
      body: form,
    });
    state.currentTaskId = upload.task_id;
    setProgress(0.02, "排队中");
    switchView("report");
    pollTask(upload.task_id);
    loadHistory();
  } catch (error) {
    showMessage(error.message);
    setProgress(0, "上传失败");
  }
}

async function pollTask(taskId) {
  window.clearTimeout(state.pollTimer);
  try {
    const task = await apiGet(`/api/tasks/${taskId}`);
    setProgress(task.progress || 0, stageText(task.stage, task.status));

    if (task.status === "completed") {
      const report = await apiGet(`/api/tasks/${taskId}/report`);
      renderReport(report);
      loadHistory();
      return;
    }

    if (task.status === "failed") {
      showMessage(task.error || "分析失败。");
      loadHistory();
      return;
    }

    state.pollTimer = window.setTimeout(() => pollTask(taskId), 2500);
  } catch (error) {
    showMessage(error.message);
  }
}

async function loadHistory() {
  try {
    const data = await apiGet(`/api/history?user_id=${encodeURIComponent(state.userId)}&limit=30`);
    renderHistory(data.items || []);
  } catch (error) {
    els.historyList.innerHTML = emptyText(error.message);
  }
}

async function loadDemoSample() {
  clearMessage();
  try {
    const data = await apiGet("/api/demo/sample");
    if (data.report) {
      renderReport(data.report);
      switchView("report");
    }
  } catch (error) {
    showMessage(error.message);
  }
}

function renderHistory(items) {
  if (!items.length) {
    els.historyList.innerHTML = emptyText("当前 user_id 还没有历史记录。");
    return;
  }

  els.historyList.innerHTML = items.map((item) => {
    const summary = item.summary || {};
    const thumb = item.thumbnail ? absoluteUrl(item.thumbnail) : "";
    return `
      <article class="task-card" data-task-id="${escapeHtml(item.task_id)}">
        ${thumb ? `<img class="task-thumb" src="${thumb}" alt="任务缩略图">` : `<div class="task-thumb"></div>`}
        <div class="task-title">
          <strong title="${escapeHtml(item.video_name || item.task_id)}">${escapeHtml(item.video_name || item.task_id)}</strong>
          <span class="badge ${escapeHtml(item.status)}">${escapeHtml(statusText(item.status))}</span>
        </div>
        <div class="task-metrics">
          ${metricHtml("强度", valueOrDash(summary.intensity_score))}
          ${metricHtml("最高速度", formatNumber(summary.max_speed_mps, "m/s"))}
        </div>
      </article>
    `;
  }).join("");

  els.historyList.querySelectorAll(".task-card").forEach((card) => {
    card.addEventListener("click", () => openTask(card.dataset.taskId));
  });
}

async function openTask(taskId) {
  clearMessage();
  try {
    const task = await apiGet(`/api/tasks/${taskId}`);
    state.currentTaskId = taskId;
    switchView("report");
    if (task.status === "completed") {
      const report = await apiGet(`/api/tasks/${taskId}/report`);
      renderReport(report);
    } else if (task.status === "failed") {
      showMessage(task.error || "该任务分析失败。");
    } else {
      setProgress(task.progress || 0, stageText(task.stage, task.status));
      pollTask(taskId);
    }
  } catch (error) {
    showMessage(error.message);
  }
}

function renderReport(report) {
  const summary = report.summary || {};
  const video = report.video || {};
  const files = report.files || {};

  els.reportSubtitle.textContent = video.name ? `${video.name} · ${formatNumber(video.duration_sec, "秒")}` : "报告已载入";
  els.summaryGrid.innerHTML = [
    metricHtml("总移动距离", formatNumber(summary.total_distance_m, "m")),
    metricHtml("最高速度", formatNumber(summary.max_speed_mps, "m/s")),
    metricHtml("平均速度", formatNumber(summary.avg_speed_mps, "m/s")),
    metricHtml("训练强度", valueOrDash(summary.intensity_score)),
    metricHtml("识别帧数", valueOrDash(summary.detected_frames)),
    metricHtml("羽毛球帧数", valueOrDash(summary.shuttlecock_frames)),
  ].join("");

  setMedia(els.highlightVideo, els.highlightEmpty, els.highlightLink, files.highlight);
  setMedia(els.analysisVideo, els.analysisEmpty, els.analysisVideoLink, files.analysis_video);
  setImage(els.heatmapImage, els.heatmapEmpty, els.heatmapLink, files.heatmap);
  setImage(els.trajectoryImage, els.trajectoryEmpty, els.trajectoryLink, files.trajectory);

  els.adviceList.innerHTML = renderCoaching(report.coaching, report.advice || []);

  if (report.task_id) {
    state.currentTaskId = report.task_id;
  }
}

function renderCoaching(coaching, legacyAdvice) {
  const groups = [
    ["strengths", "当前优点", "暂无明显优点。"],
    ["weaknesses", "目前缺点", "暂无明显缺点。"],
    ["improvements", "改进建议", "暂无改进建议。"],
  ];
  const hasStructured =
    coaching &&
    groups.some(([key]) => Array.isArray(coaching[key]) && coaching[key].length > 0);

  if (!hasStructured) {
    return legacyAdvice.length
      ? legacyAdvice.map((item) => `<li>${escapeHtml(item)}</li>`).join("")
      : "<li>暂无训练建议。</li>";
  }

  return groups
    .map(([key, label, emptyText]) => {
      const items = Array.isArray(coaching[key]) ? coaching[key] : [];
      const body = items.length
        ? `<ul class="coaching-items">${items.map(coachingItemHtml).join("")}</ul>`
        : `<p>${emptyText}</p>`;
      return `<li class="coaching-group"><strong>${label}</strong>${body}</li>`;
    })
    .join("");
}

function coachingItemHtml(item) {
  const title = escapeHtml(item.title || "");
  const detail = escapeHtml(item.detail || "");
  const basis = escapeHtml(item.basis || "");
  const trainingFocus = escapeHtml(item.training_focus || "");
  return `
    <li>
      <b>${title}</b>
      ${basis ? `<span>${basis}</span>` : ""}
      ${detail ? `<p>${detail}</p>` : ""}
      ${trainingFocus ? `<em>${trainingFocus}</em>` : ""}
    </li>
  `;
}

function setMedia(videoEl, emptyEl, linkEl, path) {
  if (!path) {
    videoEl.removeAttribute("src");
    videoEl.load();
    videoEl.hidden = true;
    emptyEl.hidden = false;
    linkEl.hidden = true;
    return;
  }
  const url = absoluteUrl(path);
  videoEl.src = url;
  videoEl.hidden = false;
  emptyEl.hidden = true;
  linkEl.href = url;
  linkEl.hidden = false;
}

function setImage(imageEl, emptyEl, linkEl, path) {
  if (!path) {
    imageEl.removeAttribute("src");
    imageEl.hidden = true;
    emptyEl.hidden = false;
    linkEl.hidden = true;
    return;
  }
  const url = absoluteUrl(path);
  imageEl.src = url;
  imageEl.hidden = false;
  emptyEl.hidden = true;
  linkEl.href = url;
  linkEl.hidden = false;
}

function switchView(name) {
  els.tabs.forEach((tab) => tab.classList.toggle("is-active", tab.dataset.view === name));
  els.views.forEach((view) => view.classList.toggle("is-active", view.id === `${name}View`));
}

function setProgress(progress, label) {
  const value = Math.max(0, Math.min(1, Number(progress) || 0));
  els.progressWrap.hidden = false;
  els.taskStage.textContent = label;
  els.taskPercent.textContent = `${Math.round(value * 100)}%`;
  els.progressFill.style.width = `${Math.round(value * 100)}%`;
}

function normalizeCornersJson(value) {
  const raw = (value || "").trim();
  if (!raw) return "";
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (_error) {
    throw new Error("手动角点必须是合法 JSON，例如 [[824,711],[1728,711],[2093,1382],[459,1382]]。");
  }
  if (!Array.isArray(parsed) || parsed.length !== 4) {
    throw new Error("手动角点必须包含 4 个点，顺序为左上、右上、右下、左下。");
  }
  const normalized = parsed.map((point) => {
    if (!Array.isArray(point) || point.length !== 2) {
      throw new Error("每个角点必须是 [x, y]。");
    }
    const x = Number(point[0]);
    const y = Number(point[1]);
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0) {
      throw new Error("角点坐标必须是非负数字。");
    }
    return [Math.round(x), Math.round(y)];
  });
  return JSON.stringify(normalized);
}

async function apiGet(path) {
  return apiRequest(path);
}

async function apiRequest(path, options = {}) {
  const response = await fetch(`${apiBase}${path}`, options);
  const contentType = response.headers.get("content-type") || "";
  const data = contentType.includes("application/json") ? await response.json() : await response.text();
  if (!response.ok) {
    throw new Error(parseApiError(data, response.status));
  }
  return data;
}

function parseApiError(data, status) {
  const detail = data && data.detail;
  if (detail && typeof detail === "object") {
    return [detail.message, detail.hint, detail.code ? `错误码：${detail.code}` : ""].filter(Boolean).join(" ");
  }
  if (typeof detail === "string") return detail;
  return `请求失败，HTTP ${status}`;
}

function showMessage(text) {
  els.messageBox.hidden = false;
  els.messageBox.textContent = text;
}

function clearMessage() {
  els.messageBox.hidden = true;
  els.messageBox.textContent = "";
}

function metricHtml(label, value) {
  return `<div class="metric"><span>${escapeHtml(label)}</span><strong>${escapeHtml(String(value))}</strong></div>`;
}

function emptyText(text) {
  return `<div class="notice">${escapeHtml(text)}</div>`;
}

function absoluteUrl(path) {
  if (!path) return "";
  if (/^https?:\/\//i.test(path)) return path;
  return `${apiBase}${path.startsWith("/") ? path : `/${path}`}`;
}

function getStoredUserId() {
  const stored = localStorage.getItem("good_badminton_user_id");
  if (stored) return sanitizeUserId(stored);
  const created = createGuestId();
  localStorage.setItem("good_badminton_user_id", created);
  return created;
}

function createGuestId() {
  const random = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return `guest_${random}`.slice(0, 64);
}

function sanitizeUserId(value) {
  return (value || "guest").trim().replace(/[^\w.-]/g, "_").slice(0, 64) || "guest";
}

function statusText(status) {
  return {
    queued: "排队",
    processing: "分析中",
    completed: "完成",
    failed: "失败",
  }[status] || status || "-";
}

function stageText(stage, status) {
  return {
    queued: "排队中",
    preparing_court: "识别球场",
    analyzing_video: "分析视频",
    building_highlight: "生成集锦",
    building_report: "生成报告",
    completed: "已完成",
    failed: "失败",
  }[stage] || statusText(status);
}

function formatNumber(value, unit) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return "-";
  const number = Number(value);
  const formatted = Math.abs(number) >= 100 ? number.toFixed(0) : number.toFixed(2).replace(/\.?0+$/, "");
  return unit ? `${formatted} ${unit}` : formatted;
}

function valueOrDash(value) {
  return value === null || value === undefined ? "-" : value;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
