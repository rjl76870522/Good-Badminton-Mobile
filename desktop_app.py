"""Good-Badminton 桌面版 — 智能模板 + 角点确认"""
import os, sys, threading, subprocess
from pathlib import Path

import customtkinter as ctk
from tkinter import filedialog, messagebox
from PIL import Image
import cv2
import imageio_ffmpeg
import numpy as np

_FFMPEG_EXE = imageio_ffmpeg.get_ffmpeg_exe()
_FFMPEG_DIR = os.path.dirname(_FFMPEG_EXE)
os.environ["PATH"] = _FFMPEG_DIR + os.pathsep + os.environ.get("PATH", "")
os.chdir(Path(__file__).parent)

from badminton_analysis.system import load_runtime_dependencies, BadmintonAnalysisSystem
from badminton_analysis.court.mapper import auto_detect_preview, resolve_court_corners, compute_expanded_roi
from badminton_analysis.court.detector import auto_detect_court_corners, render_auto_court_preview

ctk.set_appearance_mode("Dark")
ctk.set_default_color_theme("green")

BG, CARD, ACCENT = "#1a1a2e", "#16213e", "#0f3460"
GREEN, ORANGE, TEXT = "#4ecca3", "#e94560", "#e0e0e0"


class ModernApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("Good-Badminton 🏸")
        self.geometry("1000+100+50")
        self.configure(fg_color=BG)

        # state
        self._vars()
        self._running = False
        self._video_playing = False
        self._cap = None
        self._after_id = None
        self._preview_path = None

        threading.Thread(target=load_runtime_dependencies, daemon=True).start()
        self._build_ui()

    def _vars(self):
        self.video_path = ctk.StringVar()
        self.template_path = ctk.StringVar()
        self.output_dir = ctk.StringVar()
        self.pose_family = ctk.StringVar(value="yolo-pose")
        self.language = ctk.StringVar(value="中文")
        self.lang_code = "zh"
        self.show_skeletons = ctk.BooleanVar(value=True)
        self.show_traj = ctk.BooleanVar(value=True)
        self.show_court = ctk.BooleanVar(value=True)
        self.show_shuttle = ctk.BooleanVar(value=True)
        self.show_stats = ctk.BooleanVar(value=True)
        self.keep_audio = ctk.BooleanVar(value=False)
        self.corners_cache = None

    def _log(self, msg):
        self.log_box.configure(state="normal")
        self.log_box.insert("end", msg + "\n")
        self.log_box.see("end")
        self.log_box.configure(state="disabled")
        self.update()

    def _pick_file(self, var, title, ftypes):
        p = filedialog.askopenfilename(title=title, filetypes=ftypes)
        if p:
            var.set(p)
            if var == self.video_path and not self.output_dir.get():
                self.output_dir.set(os.path.dirname(p))

    def _pick_folder(self, var, title):
        p = filedialog.askdirectory(title=title)
        if p:
            var.set(p)

    def _switch_lang(self, val):
        self.lang_code = "zh" if val == "中文" else "en"

    # ══════════ UI ══════════
    def _build_ui(self):
        self.grid_columnconfigure(0, weight=3)
        self.grid_columnconfigure(1, weight=2)
        self.grid_rowconfigure(0, weight=1)

        self._build_left()
        self._build_right()

    def _build_left(self):
        left = ctk.CTkFrame(self, fg_color=BG)
        left.grid(row=0, column=0, sticky="nsew", padx=(8, 4), pady=8)

        ctk.CTkLabel(left, text="🏸  Good-Badminton", font=ctk.CTkFont("微软雅黑", 20, "bold"),
                     text_color=GREEN).pack(anchor="w", padx=12, pady=(8, 0))
        ctk.CTkLabel(left, text="AI 羽毛球视频分析", font=ctk.CTkFont("微软雅黑", 11),
                     text_color="#aaa").pack(anchor="w", padx=12, pady=(0, 8))

        # ── 输入 ──
        f1 = ctk.CTkFrame(left, fg_color=CARD, corner_radius=10)
        f1.pack(fill="x", padx=8, pady=4)
        ctk.CTkLabel(f1, text="📁 输入文件", font=ctk.CTkFont("微软雅黑", 13, "bold"),
                     text_color=GREEN).pack(anchor="w", padx=12, pady=(8, 4))
        for lbl, btn, var, fn in [
            ("视频", "选择", self.video_path, lambda: self._pick_file(self.video_path, "选择视频", [("视频", "*.mp4 *.avi *.mov"), ("所有", "*.*")])),
            ("模板", "选择", self.template_path, lambda: self._pick_file(self.template_path, "选择模板", [("图片", "*.png *.jpg"), ("所有", "*.*")])),
            ("输出", "目录", self.output_dir, lambda: self._pick_folder(self.output_dir, "选择输出目录")),
        ]:
            r = ctk.CTkFrame(f1, fg_color="transparent")
            r.pack(fill="x", padx=12, pady=2)
            ctk.CTkLabel(r, text=lbl, width=32, text_color=TEXT).pack(side="left")
            ctk.CTkEntry(r, textvariable=var, height=28).pack(side="left", fill="x", expand=True, padx=4)
            ctk.CTkButton(r, text=btn, width=50, height=28, fg_color=ACCENT, hover_color=GREEN, command=fn,
                          font=ctk.CTkFont(size=11)).pack(side="right")

        # ── 模板截取 + 角点 ──
        f2 = ctk.CTkFrame(left, fg_color=CARD, corner_radius=10)
        f2.pack(fill="x", padx=8, pady=4)
        ctk.CTkLabel(f2, text="📍 球场面检测", font=ctk.CTkFont("微软雅黑", 13, "bold"),
                     text_color=GREEN).pack(anchor="w", padx=12, pady=(8, 2))

        r2a = ctk.CTkFrame(f2, fg_color="transparent")
        r2a.pack(fill="x", padx=12, pady=(0, 2))
        ctk.CTkButton(r2a, text="🎯  从视频智能截取模板", command=self._smart_extract_template,
                      fg_color="#2a6e4f", hover_color=GREEN, height=30,
                      font=ctk.CTkFont(size=11)).pack(side="left")
        self.extract_label = ctk.CTkLabel(r2a, text="", text_color="#888", font=ctk.CTkFont(size=10))
        self.extract_label.pack(side="left", padx=10)

        r2b = ctk.CTkFrame(f2, fg_color="transparent")
        r2b.pack(fill="x", padx=12, pady=(2, 2))
        ctk.CTkButton(r2b, text="🔍  自动检测角点", command=self._detect_corners,
                      fg_color=ACCENT, hover_color=GREEN, height=32).pack(side="left")
        ctk.CTkButton(r2b, text="👁 预览角点", command=self._preview_corners,
                      fg_color="#333", hover_color="#555", height=32,
                      font=ctk.CTkFont(size=11)).pack(side="left", padx=4)
        ctk.CTkButton(r2b, text="✏️ 手动重标", command=self._manual_annotate,
                      fg_color="#333", hover_color="#555", height=32,
                      font=ctk.CTkFont(size=11)).pack(side="left")
        self.corner_label = ctk.CTkLabel(r2b, text="⏳ 未检测", text_color="#888", font=ctk.CTkFont(size=11))
        self.corner_label.pack(side="left", padx=12)

        # ── 设置 ──
        f3 = ctk.CTkFrame(left, fg_color=CARD, corner_radius=10)
        f3.pack(fill="x", padx=8, pady=4)
        ctk.CTkLabel(f3, text="⚙️ 设置", font=ctk.CTkFont("微软雅黑", 13, "bold"),
                     text_color=GREEN).pack(anchor="w", padx=12, pady=(8, 2))
        sf = ctk.CTkFrame(f3, fg_color="transparent")
        sf.pack(fill="x", padx=12, pady=4)
        ctk.CTkLabel(sf, text="姿态模型", text_color=TEXT, font=ctk.CTkFont(size=11)).grid(row=0, column=0, sticky="w")
        ctk.CTkOptionMenu(sf, variable=self.pose_family, values=["yolo-pose", "rtmpose", "rtmo"],
                          fg_color=ACCENT, button_color=GREEN).grid(row=0, column=1, padx=(6, 20))
        ctk.CTkLabel(sf, text="语言", text_color=TEXT, font=ctk.CTkFont(size=11)).grid(row=0, column=2, padx=(0, 4))
        ctk.CTkOptionMenu(sf, variable=self.language, values=["中文", "English"],
                          fg_color=ACCENT, button_color=GREEN,
                          command=self._switch_lang).grid(row=0, column=3)

        cb_f = ctk.CTkFrame(f3, fg_color="transparent")
        cb_f.pack(fill="x", padx=12, pady=(0, 8))
        for i, (var, text) in enumerate([
            (self.show_skeletons, "🦴骨架"), (self.show_traj, "👣轨迹"),
            (self.show_court, "🗺️小地图"), (self.show_shuttle, "🏸羽球"),
            (self.show_stats, "📊统计"), (self.keep_audio, "🔊音频"),
        ]):
            ctk.CTkCheckBox(cb_f, text=text, variable=var, fg_color=GREEN).grid(row=i//3, column=i%3, sticky="w", padx=(0,8), pady=2)

        # ── 操作 ──
        f4 = ctk.CTkFrame(left, fg_color=CARD, corner_radius=10)
        f4.pack(fill="x", padx=8, pady=4)
        ctk.CTkLabel(f4, text="🚀 操作", font=ctk.CTkFont("微软雅黑", 13, "bold"),
                     text_color=GREEN).pack(anchor="w", padx=12, pady=(8, 2))
        r4 = ctk.CTkFrame(f4, fg_color="transparent")
        r4.pack(fill="x", padx=12, pady=(0, 8))
        self.btn_run = ctk.CTkButton(r4, text="▶  开始分析", command=self._run_analysis,
                                     fg_color=GREEN, hover_color="#3db88b", text_color="#111",
                                     font=ctk.CTkFont("微软雅黑", 13, "bold"), height=38, width=140)
        self.btn_run.pack(side="left", padx=(0, 8))
        self.btn_open = ctk.CTkButton(r4, text="📂 输出文件夹", command=lambda: os.startfile(os.path.abspath("outputs")),
                                      fg_color=ACCENT, hover_color=GREEN, state="disabled", height=38)
        self.btn_open.pack(side="left")

        # ── 进度 ──
        self.progress = ctk.CTkProgressBar(left, height=6, fg_color=CARD, progress_color=GREEN, corner_radius=3)
        self.progress.pack(fill="x", padx=12, pady=(4, 0))
        self.progress.set(0)
        self.progress_label = ctk.CTkLabel(left, text="", text_color="#888", font=ctk.CTkFont(size=10))
        self.progress_label.pack(anchor="w", padx=12)

        # ── 日志 ──
        self.log_box = ctk.CTkTextbox(left, height=120, fg_color="#0d1117", text_color="#8b949e",
                                       font=ctk.CTkFont("Consolas", 10), corner_radius=8, border_width=0)
        self.log_box.configure(state="disabled")
        self.log_box.pack(fill="x", padx=8, pady=(4, 8))
        self._log("🏸 Good-Badminton 桌面版 v0.3")
        self._log("💡 选视频 → 智能截取模板 → 检测角点 → 预览确认 → 开始分析")

    def _build_right(self):
        right = ctk.CTkFrame(self, fg_color=CARD, corner_radius=10)
        right.grid(row=0, column=1, sticky="nsew", padx=(4, 8), pady=8)
        right.grid_rowconfigure(1, weight=1)
        right.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(right, text="📸 预览", font=ctk.CTkFont("微软雅黑", 15, "bold"),
                     text_color=GREEN).grid(row=0, column=0, padx=12, pady=(10, 4), sticky="w")

        self.tab_frame = ctk.CTkFrame(right, fg_color="transparent")
        self.tab_frame.grid(row=1, column=0, sticky="nsew", padx=8, pady=(0, 4))

        self._show_placeholder("完成分析后在此预览结果")

        btn_f = ctk.CTkFrame(right, fg_color="transparent")
        btn_f.grid(row=2, column=0, padx=8, pady=(0, 10))
        self.tab_btns = []
        for txt, cmd in [
            ("🔥 热力图", lambda: self._show_img("heatmaps", "match_heatmap.png")),
            ("🔵 散点图", lambda: self._show_img("scatter_plots", "match_scatter.png")),
            ("🎬 视频", self._play_video),
        ]:
            b = ctk.CTkButton(btn_f, text=txt, fg_color=ACCENT, hover_color=GREEN,
                              font=ctk.CTkFont(size=11), height=28, command=cmd)
            b.pack(side="left", padx=3)
            self.tab_btns.append(b)

    def _show_placeholder(self, text="等待分析完成..."):
        for wg in self.tab_frame.winfo_children():
            wg.destroy()
        ctk.CTkLabel(self.tab_frame, text=text, font=ctk.CTkFont(size=14), text_color="#666").pack(expand=True, fill="both")

    # ══════════ 智能模板截取 ══════════
    def _smart_extract_template(self):
        video = self.video_path.get()
        if not video or not os.path.exists(video):
            messagebox.showerror("错误", "请先选择比赛视频")
            return
        self._log("🎯 正在从视频中智能搜索最佳模板帧...")
        self.extract_label.configure(text="⏳ 扫描中...", text_color="#ffa500")
        threading.Thread(target=self._do_extract, daemon=True).start()

    def _do_extract(self):
        try:
            cap = cv2.VideoCapture(self.video_path.get())
            if not cap.isOpened():
                self.after(0, lambda: self._log("❌ 无法打开视频"))
                return
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            fps = cap.get(cv2.CAP_PROP_FPS)
            dur = total / max(fps, 1)

            start, end = int(dur * 0.10 * fps), int(dur * 0.90 * fps)
            interval = int(fps * 2)
            positions = list(range(start, min(end, total), interval)) or [total // 2]

            self._log(f"📊 扫描 {len(positions)} 个候选帧 (时长 {dur:.0f}s)...")

            best_score, best_frame, best_pos = -1, None, 0
            for i, pos in enumerate(positions):
                cap.set(cv2.CAP_PROP_POS_FRAMES, pos)
                ret, frame = cap.read()
                if not ret: continue
                sc = self._score_frame(frame)
                self.after(0, lambda p=i+1, t=len(positions), s=sc:
                           self.extract_label.configure(text=f"⏳ {p}/{t} (评分:{s:.0f})"))
                if sc > best_score:
                    best_score, best_frame, best_pos = sc, frame.copy(), pos
            cap.release()

            if best_frame is None:
                self.after(0, lambda: self._log("❌ 未找到合适帧"))
                return

            save_path = os.path.join(os.path.dirname(self.video_path.get()),
                                     f"_auto_template.png")
            cv2.imwrite(save_path, best_frame)
            self.after(0, lambda: self.template_path.set(save_path))
            self.after(0, lambda: self._log(f"✅ 模板已保存 (帧#{best_pos}, 评分:{best_score:.0f})"))
            self.after(0, lambda: self.extract_label.configure(
                text=f"✅ 帧#{best_pos} (评分{best_score:.0f})", text_color=GREEN))
            self.after(300, self._detect_corners)
        except Exception as e:
            self.after(0, lambda: self._log(f"❌ 截取出错: {e}"))

    def _score_frame(self, frame):
        h, w = frame.shape[:2]
        small = cv2.resize(frame, (int(w * 480/h), 480)) if h > 0 else frame
        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        edges = cv2.Canny(gray, 50, 150)
        edge = min(1, np.count_nonzero(edges) / (gray.size * 0.15))
        bright = 1 - abs(gray.mean() - 90) / 90
        var = min(1, gray.std() / 50)
        hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)
        green = min(1, ((hsv[:,:,0] >= 35) & (hsv[:,:,0] <= 95) & (hsv[:,:,1] >= 30)).sum() / gray.size / 0.2)
        return max(0, edge * 40 + max(0, bright) * 25 + var * 20 + green * 15)

    # ══════════ 角点检测 ══════════
    def _detect_corners(self):
        path = self.template_path.get()
        if not path or not os.path.exists(path):
            messagebox.showerror("错误", "请先选择球场模板图片")
            return
        self._log("🔍 正在自动检测球场角点...")
        self.corner_label.configure(text="⏳ 检测中...", text_color="#ffa500")
        threading.Thread(target=self._do_detect, daemon=True).start()

    def _do_detect(self):
        try:
            img = cv2.imread(self.template_path.get())
            if img is None:
                self.after(0, lambda: messagebox.showerror("错误", "无法读取模板图片"))
                return

            # Use the optimized multi-stage detection
            corners, mask, debug = auto_detect_court_corners(img)

            if corners and len(corners) == 4:
                roi = compute_expanded_roi(corners, img.shape)
                preview = render_auto_court_preview(img, corners, roi, debug)
                result = resolve_court_corners(img, manual_corners=corners)
                self.corners_cache = result

                preview_path = os.path.join(os.path.dirname(self.template_path.get()), "_court_preview.png")
                cv2.imwrite(preview_path, preview)
                self._preview_path = preview_path

                score = debug.get("score", 0) if debug else 0
                self.after(0, lambda: self.corner_label.configure(
                    text=f"✅ 检测到 4 个角点 (评分:{score:.0f})", text_color=GREEN))
                self._log(f"✅ 角点检测成功 (评分:{score:.0f})")

                # Auto-display preview
                self.after(100, self._preview_corners)
                return

            self._log(f"❌ 自动检测失败")
            self.after(0, lambda: self.corner_label.configure(text="❌ 检测失败", text_color=ORANGE))
            self.after(0, self._manual_annotate)
        except Exception as e:
            self.after(0, lambda: messagebox.showerror("检测失败", str(e)))

    def _preview_corners(self):
        path = getattr(self, "_preview_path", None)
        if not path or not os.path.exists(path):
            self._log("⚠️ 未找到角点预览图，请先检测角点")
            return
        try:
            pil_img = Image.open(path)
            max_w, max_h = 460, 360
            w, h = pil_img.size
            scale = min(max_w / w, max_h / h, 1.0)
            pil_img = pil_img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
            ctk_img = ctk.CTkImage(pil_img, size=pil_img.size)

            for wg in self.tab_frame.winfo_children():
                wg.destroy()

            ctk.CTkLabel(self.tab_frame, text="📍 角点检测预览",
                         font=ctk.CTkFont("微软雅黑", 13, "bold"), text_color=GREEN).pack(anchor="w", padx=8, pady=(4, 2))
            ctk.CTkLabel(self.tab_frame, text="绿色框=球场 · 蓝色框=分析区 · 确认是否正确",
                         font=ctk.CTkFont(size=10), text_color="#aaa").pack(anchor="w", padx=8)
            ctk.CTkLabel(self.tab_frame, image=ctk_img, text="").pack(expand=True, fill="both", pady=4)

            ctrl = ctk.CTkFrame(self.tab_frame, fg_color="transparent")
            ctrl.pack(fill="x", padx=8, pady=(2, 6))
            ctk.CTkButton(ctrl, text="✅ 满意，开始分析", command=self._run_analysis,
                          fg_color=GREEN, hover_color="#3db88b", text_color="#111",
                          font=ctk.CTkFont("微软雅黑", 12, "bold"), height=34).pack(side="left")
            ctk.CTkButton(ctrl, text="🔄 重新检测", command=self._detect_corners,
                          fg_color="#555", hover_color="#777", height=34).pack(side="left", padx=6)
            ctk.CTkButton(ctrl, text="✏️ 手动标注", command=self._manual_annotate,
                          fg_color="#555", hover_color="#777", height=34).pack(side="left")

            self._log("📸 请查看角点预览，满意可点击「开始分析」")
        except Exception as e:
            self._log(f"❌ 预览出错: {e}")

    def _manual_annotate(self):
        self.corner_label.configure(text="✏️ 依次点击：左上→右上→右下→左下", text_color="#ffa500")
        self._log("弹出标注窗口，依次点击 4 个角点")
        try:
            img = cv2.imread(self.template_path.get())
            from badminton_analysis.court.mapper import annotate_court
            corners, roi_corners, mid_height = annotate_court(img)
            if corners and len(corners) == 4:
                self.corners_cache = (corners, roi_corners, mid_height)
                self.corner_label.configure(text="✅ 手动标注完成", text_color=GREEN)
                self._log(f"✅ 手动标注完成: {corners}")

                preview = img.copy()
                pts = np.array([[int(c[0]), int(c[1])] for c in corners], dtype=np.int32)
                cv2.polylines(preview, [pts], True, (0, 255, 0), 3)
                for idx, pt in enumerate(corners, 1):
                    cv2.circle(preview, pt, 6, (0, 0, 255), -1)
                    cv2.putText(preview, str(idx), (pt[0] + 8, pt[1] - 8),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.75, (0, 0, 255), 2)
                preview_path = os.path.join(os.path.dirname(self.template_path.get()), "_court_preview.png")
                cv2.imwrite(preview_path, preview)
                self._preview_path = preview_path
                self.after(100, self._preview_corners)
            else:
                self.corner_label.configure(text="❌ 标注取消", text_color=ORANGE)
        except Exception as e:
            self.corner_label.configure(text="❌ 标注失败", text_color=ORANGE)
            self._log(f"❌ 标注出错: {e}")

    # ══════════ 分析 ══════════
    def _run_analysis(self):
        if self._running: return
        if not self.video_path.get() or not os.path.exists(self.video_path.get()):
            messagebox.showerror("错误", "请选择有效的视频文件")
            return
        if not self.template_path.get() or not os.path.exists(self.template_path.get()):
            messagebox.showerror("错误", "请选择球场模板图片")
            return
        if self.corners_cache is None:
            self._detect_corners()
            return

        self._running = True
        self.btn_run.configure(state="disabled", text="⏳ 分析中...")
        self.progress.set(0)
        self._log("\n" + "━" * 40 + "\n🚀 开始分析...")
        threading.Thread(target=self._do_run, daemon=True).start()

    def _do_run(self):
        try:
            video = self.video_path.get()
            template = self.template_path.get()
            lang = self.lang_code
            vid_name = os.path.splitext(os.path.basename(video))[0]
            out_dir = self.output_dir.get() or os.path.join("outputs", vid_name)
            os.makedirs(out_dir, exist_ok=True)

            corners, roi_corners, mid_height = self.corners_cache
            with open(os.path.join(out_dir, "court_annotations.txt"), "w") as f:
                f.write(f"corners={corners}\nroi_corners={roi_corners}\nmid_height={mid_height}\n")

            system = BadmintonAnalysisSystem(
                video, show_display=False,
                show_skeletons=self.show_skeletons.get(),
                show_player_trajectories=self.show_traj.get(),
                show_court_trajectory=self.show_court.get(),
                show_shuttlecock_trajectory=self.show_shuttle.get(),
                show_player_stats=self.show_stats.get(),
                show_performance_stats=False, save_images=False,
                language=lang, output_dir=out_dir,
                ball_model_path="weights/yolo11s-ball.pt",
                template_path=template, pose_mode="balanced",
                pose_family=self.pose_family.get(),
                yolo_pose_model="weights/yolo11n-pose.pt",
                show_pose_roi=False)
            system.keep_audio = self.keep_audio.get()

            cap = cv2.VideoCapture(video)
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            cap.release()

            def progress_cb(frame, total_f):
                pct = frame / total_f
                self.after(0, lambda: self.progress.configure(value=pct))
                self.after(0, lambda: self.progress_label.configure(text=f"⏳ {frame}/{total_f} ({int(pct*100)}%)"))

            self._log(f"📊 总帧数: {total}")
            system.process_video(progress_callback=progress_cb)

            # Retry if no detections
            line_count = sum(1 for _ in open(system.detections_path) if _.strip()) if os.path.exists(system.detections_path) else 0
            self._log(f"📄 detections.jsonl: {line_count} 条记录")
            if line_count == 0:
                self._log("⚠️ 没有记录，降低模板匹配阈值重试...")
                system.is_court_view = lambda f, t: True
                system.process_video(progress_callback=progress_cb)

            self._log("📊 生成位置可视化...")
            if lang == "en":
                from badminton_analysis.visualization.player_positions_en import analyze_player_positions
            else:
                from badminton_analysis.visualization.player_positions_zh import analyze_player_positions
            analyze_player_positions(system.detections_path,
                                     os.path.join(out_dir, "position_visualizations"), fps=system.fps)

            # Transcode video
            temp_video = os.path.join(out_dir, f"temp_detect_{vid_name}.mp4")
            final_video = os.path.join(out_dir, f"detect_{vid_name}.mp4")
            if os.path.exists(temp_video):
                self._log("🎬 转码视频...")
                ret = subprocess.run([_FFMPEG_EXE, "-y", "-i", temp_video, "-c:v", "libx264", "-preset", "fast",
                                     "-crf", "20", "-c:a", "aac", "-movflags", "+faststart", final_video],
                                    capture_output=True, timeout=300)
                if ret.returncode != 0:
                    import shutil; shutil.copy2(temp_video, final_video)

            self.after(0, lambda: self._log(f"\n✅ 分析完成！结果: {out_dir}"))
            self.after(0, lambda: self.btn_open.configure(state="normal"))
            self.after(0, lambda: self.progress_label.configure(text="✅ 完成！"))
            self.after(0, lambda: self.progress.set(1))
            self.after(500, lambda: self._show_img("heatmaps", "match_heatmap.png", base_dir=out_dir))
        except Exception as e:
            self.after(0, lambda: messagebox.showerror("分析失败", str(e)))
            self._log(f"❌ 错误: {e}")
        finally:
            self._running = False
            self.after(0, lambda: self.btn_run.configure(state="normal", text="▶  开始分析"))

    # ══════════ 预览 ══════════
    def _show_img(self, subdir, filename, base_dir=None):
        self._stop_video()
        if base_dir is None:
            video = self.video_path.get()
            base_dir = self.output_dir.get() or os.path.join("outputs", os.path.splitext(os.path.basename(video))[0])
        path = os.path.join(base_dir, "position_visualizations", subdir, filename)
        if not os.path.exists(path):
            alt = os.path.join(base_dir, "position_visualizations", subdir)
            if os.path.isdir(alt):
                files = [f for f in os.listdir(alt) if f.endswith(".png")]
                path = os.path.join(alt, files[0]) if files else ""
        if os.path.exists(path):
            try:
                pil_img = Image.open(path)
                max_w, max_h = 460, 460
                w, h = pil_img.size
                scale = min(max_w / w, max_h / h, 1.0)
                pil_img = pil_img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
                ctk_img = ctk.CTkImage(pil_img, size=pil_img.size)
                for wg in self.tab_frame.winfo_children():
                    wg.destroy()
                ctk.CTkLabel(self.tab_frame, image=ctk_img, text="").pack(expand=True, fill="both")
            except Exception as e:
                self._log(f"❌ 图片加载失败: {e}")
        else:
            self._show_placeholder("暂无结果，请先完成分析")

    def _play_video(self):
        self._stop_video()
        video = self.video_path.get()
        out_dir = self.output_dir.get() or os.path.join("outputs", os.path.splitext(os.path.basename(video))[0])
        final = os.path.join(out_dir, f"detect_{os.path.splitext(os.path.basename(video))[0]}.mp4")
        if not os.path.exists(final):
            final = os.path.join(out_dir, f"temp_detect_{os.path.splitext(os.path.basename(video))[0]}.mp4")
        if not os.path.exists(final):
            self._show_placeholder("暂无视频，请先完成分析")
            return
        self._cap = cv2.VideoCapture(final)
        for wg in self.tab_frame.winfo_children():
            wg.destroy()
        self.video_label = ctk.CTkLabel(self.tab_frame, text="")
        self.video_label.pack(expand=True, fill="both")
        self._video_playing = True
        self._update_video()

    def _update_video(self):
        if not self._video_playing or self._cap is None:
            return
        ret, frame = self._cap.read()
        if not ret:
            self._cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            ret, frame = self._cap.read()
            if not ret: return
        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        h, w = frame.shape[:2]
        scale = min(460 / w, 420 / h, 1.0)
        frame = cv2.resize(frame, (int(w * scale), int(h * scale)))
        ctk_img = ctk.CTkImage(Image.fromarray(frame), size=(int(w*scale), int(h*scale)))
        self.video_label.configure(image=ctk_img)
        self._after_id = self.after(30, self._update_video)

    def _stop_video(self):
        self._video_playing = False
        if self._after_id:
            self.after_cancel(self._after_id); self._after_id = None
        if self._cap:
            self._cap.release(); self._cap = None


if __name__ == "__main__":
    ModernApp().mainloop()
