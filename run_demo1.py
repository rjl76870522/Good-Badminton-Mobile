"""Process demo1.mp4 with demo1.png template."""
import os, sys

os.chdir(os.path.dirname(os.path.abspath(__file__)))
ffmpeg_dir = r"C:\Users\lanld\anaconda3\Lib\site-packages\imageio_ffmpeg\binaries"
os.environ["PATH"] = ffmpeg_dir + os.pathsep + os.environ.get("PATH", "")

from badminton_analysis.system import load_runtime_dependencies, BadmintonAnalysisSystem
from badminton_analysis.court.mapper import auto_detect_preview, resolve_court_corners
import cv2

load_runtime_dependencies()

template_path = "templates/demo1.png"
video_path = "videos/demo1.mp4"

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
    print("Auto-detection failed, trying headless fallback...")
    corners, roi_corners, mid_height = resolve_court_corners(template_color)

if not corners or len(corners) != 4:
    print("Could not detect court corners. Exiting.")
    sys.exit(1)

print(f"Court corners: {corners}")
print(f"ROI: {roi_corners}")
print(f"Mid height: {mid_height}")

video_name = os.path.basename(video_path)[:-4]
save_dir = os.path.join("outputs", video_name)
os.makedirs(save_dir, exist_ok=True)

with open(os.path.join(save_dir, "court_annotations.txt"), "w") as f:
    f.write(f"corners={corners}\n")
    f.write(f"roi_corners={roi_corners}\n")
    f.write(f"mid_height={mid_height}\n")

print(f"\n=== Starting analysis: {video_path} ===")
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

print("\n=== Generating position visualizations ===")
from badminton_analysis.visualization.player_positions_zh import analyze_player_positions
analyze_player_positions(system.detections_path, os.path.join(system.save_dir, "position_visualizations"), fps=system.fps)
print(f"\nDone! Results in: {system.save_dir}")
