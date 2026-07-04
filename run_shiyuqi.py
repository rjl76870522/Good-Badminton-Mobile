"""Analyze shiyuqi cut video (skipping first 10s)."""
import os, sys
os.chdir(os.path.dirname(os.path.abspath(__file__)))

try:
    import imageio_ffmpeg

    ffmpeg_dir = os.path.dirname(imageio_ffmpeg.get_ffmpeg_exe())
    os.environ["PATH"] = ffmpeg_dir + os.pathsep + os.environ.get("PATH", "")
except Exception:
    pass

from badminton_analysis.system import load_runtime_dependencies, BadmintonAnalysisSystem
from badminton_analysis.court.mapper import auto_detect_preview, resolve_court_corners
import cv2

load_runtime_dependencies()

template_path = "templates/shiyuqi_template.png"
video_path = "videos/shiyuqi_10_45.mp4"

template_color = cv2.imread(template_path)
if template_color is None:
    print("Failed to load template!")
    sys.exit(1)

print("Auto-detecting court corners...")
corners_auto, preview = auto_detect_preview(template_color)
if corners_auto:
    print(f"Auto-detected: {corners_auto}")
    corners, roi_corners, mid_height = resolve_court_corners(template_color, manual_corners=corners_auto)
else:
    corners, roi_corners, mid_height = resolve_court_corners(template_color)

if not corners or len(corners) != 4:
    print("Could not detect court corners. Exiting.")
    sys.exit(1)

print(f"Corners: {corners}")
print(f"ROI: {roi_corners}")
print(f"Mid height: {mid_height}")

video_name = "shiyuqi"
save_dir = os.path.join("outputs", video_name)
os.makedirs(save_dir, exist_ok=True)

with open(os.path.join(save_dir, "court_annotations.txt"), "w") as f:
    f.write(f"corners={corners}\n")
    f.write(f"roi_corners={roi_corners}\n")
    f.write(f"mid_height={mid_height}\n")

print(f"\n=== Starting analysis ===")
system = BadmintonAnalysisSystem(
    video_path,
    show_display=False,
    show_skeletons=True,
    show_player_trajectories=True,
    show_court_trajectory=True,
    show_shuttlecock_trajectory=True,
    show_player_stats=True,
    show_performance_stats=False,
    save_images=False,
    language="zh",
    output_dir=save_dir,
    ball_model_path="weights/yolo11s-ball.pt",
    template_path=template_path,
    pose_mode="balanced",
    pose_family="yolo-pose",
    yolo_pose_model="weights/yolo11n-pose.pt",
    show_pose_roi=False,
)
system.keep_audio = True
system.process_video()

print("\n=== Generating position visualizations ===")
from badminton_analysis.visualization.player_positions_zh import analyze_player_positions
analyze_player_positions(system.detections_path, os.path.join(save_dir, "position_visualizations"), fps=system.fps)
print(f"\nDone! Results in: {save_dir}")
