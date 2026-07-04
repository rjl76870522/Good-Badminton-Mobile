#!/usr/bin/env python3
"""
Good-Badminton 核心分析封装
================================
将 Good-Badminton 羽毛球视频分析系统的完整流程封装为单个可调用函数，
支持作为独立脚本运行或由其他 Python 代码导入使用。

用法:
    # 命令行
    python analyze_badminton.py --video-path videos/demo.mp4 --template-path templates/demo.png

    # Python 导入
    from analyze_badminton import analyze_badminton_video
    result = analyze_badminton_video(video_path="videos/demo.mp4", template_path="templates/demo.png")
"""

import argparse
import os
import sys
import time
from typing import Callable, Dict, List, Optional, Tuple, Union


def analyze_badminton_video(
    video_path: str,
    template_path: Optional[str] = None,
    output_dir: Optional[str] = None,
    ball_model_path: str = "weights/yolo11s-ball.pt",
    pose_family: str = "yolo-pose",
    pose_mode: str = "balanced",
    yolo_pose_model: str = "weights/yolo11n-pose.pt",
    language: str = "zh",
    show_display: bool = False,
    show_skeletons: bool = True,
    show_player_trajectories: bool = True,
    show_court_trajectory: bool = True,
    show_shuttlecock_trajectory: bool = True,
    show_player_stats: bool = True,
    show_pose_roi: bool = False,
    show_performance_stats: bool = False,
    keep_audio: bool = True,
    save_images: bool = False,
    generate_position_visualizations: bool = True,
    progress_callback: Optional[Callable[[int, int], None]] = None,
    court_corners: Optional[List[Tuple[int, int]]] = None,
) -> Dict[str, Union[str, List[str], int, float]]:
    """分析羽毛球比赛视频，返回检测结果和输出文件路径。

    这是 Good-Badminton 系统的核心封装函数，涵盖从球场标注、
    姿态检测、羽毛球追踪到视频输出的完整流程。

    Args:
        video_path: 输入视频文件路径（必填）。
        template_path: 球场模板图像路径。
            - 若提供，直接使用该文件。
            - 若为 None，在有桌面环境时会弹出文件选择框。
            - 在无头服务器上必须提供此参数。
        output_dir: 输出目录。默认为 outputs/<视频文件名>/。
        ball_model_path: YOLO 羽毛球检测模型路径。
        pose_family: 姿态模型族。"rtmpose"、"rtmo" 或 "yolo-pose"。
        pose_mode: RTMPose/RTMO 档位。"lightweight"、"balanced"、"performance"。
        yolo_pose_model: YOLO pose 模型路径或名称（仅 pose_family="yolo-pose" 时使用）。
        language: 界面语言。"zh"（中文）或 "en"（英文）。
        show_display: 是否实时显示 OpenCV 预览窗口。
        show_skeletons: 是否绘制人体骨架。
        show_player_trajectories: 是否绘制球员轨迹。
        show_court_trajectory: 是否显示球场轨迹叠加层。
        show_shuttlecock_trajectory: 是否显示羽毛球轨迹。
        show_player_stats: 是否显示球员统计信息。
        show_pose_roi: 是否显示姿态检测 ROI 框。
        show_performance_stats: 是否打印每帧性能耗时。
        keep_audio: 是否保留原视频音频。
        save_images: 是否保存每帧处理后的图像。
        generate_position_visualizations: 是否生成热力图和散点图。
        progress_callback: 可选的回调函数，接收 (当前帧数, 总帧数)。
            可用于在 GUI 或 WebUI 中显示进度条。
        court_corners: 可选的手动球场四角点坐标列表，格式为
            [(x1,y1), (x2,y2), (x3,y3), (x4,y4)]，分别对应
            左上、右上、右下、左下。提供后将跳过自动球场检测。

    Returns:
        包含以下键的字典:
            - "output_dir" (str): 输出目录路径
            - "video" (str): 标注后的输出视频路径
            - "metadata" (str): metadata.json 路径
            - "detections" (str): detections.jsonl 路径
            - "visualizations" (List[str]): 生成的可视化图片路径列表
            - "total_frames" (int): 视频总帧数
            - "fps" (float): 视频帧率
            - "processing_time_sec" (float): 处理耗时（秒）
            - "speedup_ratio" (float): 处理速度比（处理耗时/视频时长）

    Raises:
        FileNotFoundError: 视频文件或模型文件不存在。
        RuntimeError: 球场标注失败或其他运行时错误。
    """
    # ============================================================
    # 1. 验证输入
    # ============================================================
    if not os.path.exists(video_path):
        raise FileNotFoundError(f"输入视频文件不存在: {video_path}")
    if not os.path.exists(ball_model_path):
        raise FileNotFoundError(
            f"羽毛球检测模型不存在: {ball_model_path}\n"
            f"请从 https://github.com/yo-WASSUP/Good-Badminton/releases 下载"
        )

    # ============================================================
    # 2. 加载运行时依赖（延迟加载以支持 --help）
    # ============================================================
    from badminton_analysis.system import BadmintonAnalysisSystem, load_runtime_dependencies
    load_runtime_dependencies()

    import cv2
    import numpy as np

    # ============================================================
    # 3. 准备输出目录
    # ============================================================
    video_name = os.path.splitext(os.path.basename(video_path))[0]
    if output_dir is None:
        output_dir = os.path.join("outputs", video_name)
    os.makedirs(output_dir, exist_ok=True)

    # ============================================================
    # 4. 球场标注
    # ============================================================
    if template_path is not None and not os.path.exists(template_path):
        raise FileNotFoundError(f"球场模板图像不存在: {template_path}")

    _temp_template_created = False
    if court_corners is not None:
        # 用户提供了手动角点 → 跳过自动检测并预写入标注文件
        print("使用手动指定的球场角点...")
        from badminton_analysis.court.mapper import CourtMapper, compute_expanded_roi, resolve_court_corners

        # 确保有模板图像用于解析角点坐标
        template_color = None
        if template_path and os.path.exists(template_path):
            template_color = cv2.imread(template_path)
        if template_color is None:
            # 没有模板图时，从视频第一帧提取作为模板
            cap = cv2.VideoCapture(video_path)
            if not cap.isOpened():
                raise RuntimeError(f"无法打开视频: {video_path}")
            ret, template_color = cap.read()
            cap.release()
            if not ret:
                raise RuntimeError("无法从视频中读取第一帧作为球场标注基准")
            # 将这一帧保存为临时模板，供后续 court view 检测使用
            temp_template_path = os.path.join(output_dir, "_auto_template.png")
            cv2.imwrite(temp_template_path, template_color)
            if template_path is None:
                template_path = temp_template_path
                _temp_template_created = True

        corners, roi_corners, mid_height = resolve_court_corners(
            template_color, manual_corners=court_corners
        )
        if not corners or len(corners) != 4:
            raise RuntimeError("手动角点无效，请提供 4 个 (x, y) 坐标")

        # 保存标注结果供后续复用（让 BadmintonAnalysisSystem._setup_court_annotation() 跳过 GUI）
        with open(os.path.join(output_dir, "court_annotations.txt"), "w") as f:
            f.write(f"corners={corners}\n")
            f.write(f"roi_corners={roi_corners}\n")
            f.write(f"mid_height={mid_height}\n")
        print(f"球场角点: {corners}")

    # ============================================================
    # 5. 创建分析系统并运行
    # ============================================================
    print(f"\n{'='*60}")
    print(f"开始分析: {video_path}")
    print(f"{'='*60}")

    system = BadmintonAnalysisSystem(
        video_path=video_path,
        show_display=show_display,
        show_skeletons=show_skeletons,
        show_player_trajectories=show_player_trajectories,
        show_court_trajectory=show_court_trajectory,
        show_shuttlecock_trajectory=show_shuttlecock_trajectory,
        show_player_stats=show_player_stats,
        show_performance_stats=show_performance_stats,
        save_images=save_images,
        language=language,
        output_dir=output_dir,
        ball_model_path=ball_model_path,
        template_path=template_path,
        pose_mode=pose_mode,
        pose_family=pose_family,
        yolo_pose_model=yolo_pose_model,
        show_pose_roi=show_pose_roi,
    )
    system.keep_audio = keep_audio

    start_time = time.time()
    system.process_video(progress_callback=progress_callback)
    processing_time = time.time() - start_time

    # ============================================================
    # 6. 生成位置可视化（热力图 & 散点图）
    # ============================================================
    visualization_files: List[str] = []

    if generate_position_visualizations:
        print("\n生成球员位置可视化...")
        if language == "en":
            from badminton_analysis.visualization.player_positions_en import analyze_player_positions
        else:
            from badminton_analysis.visualization.player_positions_zh import analyze_player_positions

        vis_dir = os.path.join(output_dir, "position_visualizations")
        analyze_player_positions(system.detections_path, vis_dir, fps=system.fps)

        if os.path.isdir(vis_dir):
            for root, _dirs, files in os.walk(vis_dir):
                for fname in sorted(files):
                    if fname.lower().endswith((".png", ".jpg", ".jpeg")):
                        visualization_files.append(os.path.join(root, fname))

    # ============================================================
    # 7. 收集结果
    # ============================================================
    # 从 metadata.json 获取视频信息（由 BadmintonAnalysisSystem 写入）
    total_frames = 0
    video_duration = 1.0
    try:
        import json
        with open(system.metadata_path, "r") as f:
            meta = json.load(f)
        total_frames = meta.get("video", {}).get("total_frames", 0)
        video_duration = meta.get("video", {}).get("duration_sec", 1.0)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    result = {
        "output_dir": output_dir,
        "video": system.output_video_path,
        "metadata": system.metadata_path,
        "detections": system.detections_path,
        "visualizations": visualization_files,
        "total_frames": int(total_frames),
        "fps": float(system.fps),
        "processing_time_sec": round(processing_time, 2),
        "speedup_ratio": round(processing_time / max(video_duration, 0.001), 2),
    }

    # 清理临时生成的模板文件
    if _temp_template_created and template_path and os.path.exists(template_path):
        try:
            os.remove(template_path)
        except Exception:
            pass

    print(f"\n{'='*60}")
    print(f"分析完成! 结果保存在: {output_dir}")
    print(f"处理耗时: {processing_time:.2f} 秒")
    print(f"{'='*60}")

    return result


def main():
    """命令行入口。"""
    parser = argparse.ArgumentParser(
        description="Good-Badminton 羽毛球视频分析工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python analyze_badminton.py --video-path videos/demo.mp4 --template-path templates/demo.png\n"
            "  python analyze_badminton.py --video-path videos/demo.mp4 --template-path templates/demo.png --language en\n"
            "  python analyze_badminton.py --video-path videos/demo.mp4 --pose-family rtmpose --pose-mode balanced\n"
        ),
    )
    # --- 必选参数 ---
    parser.add_argument("--video-path", required=True, help="输入视频文件路径")

    # --- 核心可选参数 ---
    parser.add_argument("--template-path", default=None, help="球场模板图像路径（不提供时自动检测或弹出选择框）")
    parser.add_argument("--output-dir", default=None, help="输出目录（默认 outputs/<视频文件名>/）")
    parser.add_argument("--ball-model", default="weights/yolo11s-ball.pt", help="YOLO 羽毛球检测模型路径")

    # --- 姿态模型参数 ---
    parser.add_argument("--pose-family", default="yolo-pose", choices=["rtmpose", "rtmo", "yolo-pose"], help="姿态模型族")
    parser.add_argument("--pose-mode", default="balanced", choices=["lightweight", "balanced", "performance"],
                        help="RTMPose / RTMO 模型档位")
    parser.add_argument("--yolo-pose-model", default="weights/yolo11n-pose.pt", help="YOLO pose 模型路径或名称")

    # --- 可视化参数 ---
    parser.add_argument("--language", default="zh", choices=["zh", "en"], help="界面语言")
    parser.add_argument("--display", action="store_true", default=False, help="显示 OpenCV 预览窗口")
    parser.add_argument("--skeletons", default=True, type=lambda x: x.lower() == "true",
                        help="是否显示人体骨架 (true/false)")
    parser.add_argument("--player-trajectories", default=True, type=lambda x: x.lower() == "true",
                        help="是否显示球员轨迹 (true/false)")
    parser.add_argument("--court-trajectory", default=True, type=lambda x: x.lower() == "true",
                        help="是否显示球场轨迹 (true/false)")
    parser.add_argument("--shuttlecock-trajectory", default=True, type=lambda x: x.lower() == "true",
                        help="是否显示羽毛球轨迹 (true/false)")
    parser.add_argument("--player-stats", default=True, type=lambda x: x.lower() == "true",
                        help="是否显示球员统计 (true/false)")
    parser.add_argument("--pose-roi", default=False, type=lambda x: x.lower() == "true",
                        help="是否显示 Pose ROI 框 (true/false)")
    parser.add_argument("--performance-stats", action="store_true", default=False, help="打印性能统计")

    # --- 输出控制 ---
    parser.add_argument("--audio", default=True, type=lambda x: x.lower() == "true", help="是否保留音频 (true/false)")
    parser.add_argument("--save-images", action="store_true", default=False, help="保存每帧处理图像")
    parser.add_argument("--no-position-viz", action="store_true", default=False,
                        help="不生成热力图和散点图（默认生成）")

    args = parser.parse_args()

    # 执行分析
    try:
        result = analyze_badminton_video(
            video_path=args.video_path,
            template_path=args.template_path,
            output_dir=args.output_dir,
            ball_model_path=args.ball_model,
            pose_family=args.pose_family,
            pose_mode=args.pose_mode,
            yolo_pose_model=args.yolo_pose_model,
            language=args.language,
            show_display=args.display,
            show_skeletons=args.skeletons,
            show_player_trajectories=args.player_trajectories,
            show_court_trajectory=args.court_trajectory,
            show_shuttlecock_trajectory=args.shuttlecock_trajectory,
            show_player_stats=args.player_stats,
            show_pose_roi=args.pose_roi,
            show_performance_stats=args.performance_stats,
            keep_audio=args.audio,
            save_images=args.save_images,
            generate_position_visualizations=not args.no_position_viz,
        )

        # 命令行打印结果摘要
        print(f"\n{'='*60}")
        print("结果摘要:")
        print(f"  输出目录:        {result['output_dir']}")
        print(f"  标注视频:        {result['video']}")
        print(f"  检测数据:        {result['detections']}")
        print(f"  元数据:          {result['metadata']}")
        print(f"  可视化图片数:    {len(result['visualizations'])}")
        print(f"  视频总帧数:      {result['total_frames']}")
        print(f"  帧率:            {result['fps']:.2f}")
        print(f"  处理耗时:        {result['processing_time_sec']:.2f}s")
        print(f"  速度比:          {result['speedup_ratio']:.2f}x")
        print(f"{'='*60}")

    except (FileNotFoundError, RuntimeError) as e:
        print(f"\n错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
