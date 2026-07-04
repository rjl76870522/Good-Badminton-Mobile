"""Headless runner: auto-detect court corners, then run analysis."""
import os, sys

os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Add ffmpeg to PATH
try:
    import imageio_ffmpeg

    ffmpeg_dir = os.path.dirname(imageio_ffmpeg.get_ffmpeg_exe())
    os.environ["PATH"] = ffmpeg_dir + os.pathsep + os.environ.get("PATH", "")
except Exception:
    pass

from badminton_analysis.system import load_runtime_dependencies, BadmintonAnalysisSystem
from badminton_analysis.court.mapper import auto_detect_preview, resolve_court_corners
import cv2

# 1. Load heavy deps
load_runtime_dependencies()

# 2. Load template and auto-detect corners
template_path = "templates/demo.png"
template_color = cv2.imread(template_path)
if template_color is None:
    print(f"Failed to load template: {template_path}")
    sys.exit(1)

print("Auto-detecting court corners...")
corners_auto, preview = auto_detect_preview(template_color)
if corners_auto:
    print(f"Auto-detected corners: {corners_auto}")
    corners, roi_corners, mid_height = resolve_court_corners(template_color, manual_corners=corners_auto)
else:
    print("Auto-detection failed, using headless fallback...")
    corners, roi_corners, mid_height = resolve_court_corners(template_color)

if not corners or len(corners) != 4:
    print("Could not detect court corners. Exiting.")
    sys.exit(1)

print(f"Court corners: {corners}")
print(f"ROI: {roi_corners}")
print(f"Mid height: {mid_height}")

# 3. Pre-write annotation file
video_name = os.path.basename("videos/demo.mp4")[:-4]
save_dir = os.path.join("outputs", video_name)
os.makedirs(save_dir, exist_ok=True)

with open(os.path.join(save_dir, "court_annotations.txt"), "w") as f:
    f.write(f"corners={corners}\n")
    f.write(f"roi_corners={roi_corners}\n")
    f.write(f"mid_height={mid_height}\n")

print(f"Annotation saved to {save_dir}/court_annotations.txt")

# 4. Run system
print("\n=== Starting video analysis ===")
system = BadmintonAnalysisSystem(
    "videos/demo.mp4",
    show_display=False,
    show_skeletons=True,
    show_player_trajectories=True,
    show_court_trajectory=True,
    show_shuttlecock_trajectory=True,
    show_player_stats=True,
    show_performance_stats=False,
    save_images=False,
    language="zh",
    output_dir=None,
    ball_model_path="weights/yolo11s-ball.pt",
    template_path=template_path,
    pose_mode="balanced",
    pose_family="yolo-pose",
    yolo_pose_model="weights/yolo11n-pose.pt",
    show_pose_roi=False,
)
system.keep_audio = True
system.process_video()

# 5. Generate position visualizations
print("\n=== Generating position visualizations ===")
from badminton_analysis.visualization.player_positions_zh import analyze_player_positions
analyze_player_positions(system.detections_path, os.path.join(system.save_dir, "position_visualizations"), fps=system.fps)
print(f"\nDone! Results in: {system.save_dir}")
