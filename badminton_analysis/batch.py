"""批量视频分析工作流

扫描目录、依次处理多个视频、生成汇总报告。
CLI 和 WebUI 共用此模块。
"""

import json
import os
import time
from datetime import datetime

# 支持的视频扩展名
_VIDEO_EXTENSIONS = {".mp4", ".avi", ".mov", ".mkv", ".webm", ".flv", ".wmv"}


def find_videos(input_dir: str) -> list[str]:
    """扫描目录下所有视频文件，按文件名排序。

    Args:
        input_dir: 要扫描的目录路径。

    Returns:
        视频文件的绝对路径列表。
    """
    if not os.path.isdir(input_dir):
        raise NotADirectoryError(f"目录不存在: {input_dir}")

    videos = []
    for name in sorted(os.listdir(input_dir)):
        ext = os.path.splitext(name)[1].lower()
        if ext in _VIDEO_EXTENSIONS:
            videos.append(os.path.join(input_dir, name))

    return videos


def _video_name(video_path: str) -> str:
    """从路径中提取视频名（不含扩展名）。"""
    return os.path.splitext(os.path.basename(video_path))[0]


def _output_exists(video_path: str) -> bool:
    """检查某个视频是否已经有输出（用于断点续跑）。"""
    name = _video_name(video_path)
    output_dir = os.path.join("outputs", name)
    metadata = os.path.join(output_dir, "metadata.json")
    output_video = os.path.join(output_dir, f"detect_{name}.mp4")
    return os.path.isfile(metadata) and os.path.isfile(output_video)


def batch_analyze(
    video_paths: list[str],
    template_path: str | None = None,
    *,
    progress_callback=None,
    **options,
) -> dict:
    """依次分析多个视频，返回汇总结果。

    Args:
        video_paths: 视频文件路径列表。
        template_path: 共用的球场模板图路径（可选）。
        progress_callback: 可选的回调 callback(current, total, video_name)。
        **options: 传递给 BadmintonAnalysisSystem 的参数（与 CLI 参数同名）。

    Returns:
        汇总字典，结构与 batch_summary.json 一致。
    """
    from badminton_analysis.system import BadmintonAnalysisSystem, load_runtime_dependencies

    load_runtime_dependencies()

    if options.get("language", "zh") == "en":
        from badminton_analysis.visualization.player_positions_en import analyze_player_positions
    else:
        from badminton_analysis.visualization.player_positions_zh import analyze_player_positions

    total = len(video_paths)
    results = []
    batch_start = time.time()

    # 构建 system 参数
    system_kwargs = {
        "show_display": False,
        "show_skeletons": _str_to_bool(options.get("skeletons", "true")),
        "show_player_trajectories": _str_to_bool(options.get("player_trajectories", "true")),
        "show_court_trajectory": _str_to_bool(options.get("court_trajectory", "true")),
        "show_shuttlecock_trajectory": _str_to_bool(options.get("shuttlecock_trajectory", "true")),
        "show_player_stats": _str_to_bool(options.get("player_stats", "true")),
        "show_performance_stats": options.get("performance_stats", False),
        "save_images": options.get("save_images", False),
        "language": options.get("language", "zh"),
        "ball_model_path": options.get("ball_model", "weights/yolo11s-ball.pt"),
        "pose_family": options.get("pose_family", "yolo-pose"),
        "pose_mode": options.get("pose_mode", "balanced"),
        "yolo_pose_model": options.get("yolo_pose_model", "weights/yolo11n-pose.pt"),
        "show_pose_roi": _str_to_bool(options.get("show_pose_roi", "true")),
    }
    keep_audio = _str_to_bool(options.get("audio", "true"))
    visualize_positions = options.get("visualize_positions", True)

    for idx, video_path in enumerate(video_paths, 1):
        video_name = _video_name(video_path)
        result = {
            "video": video_path,
            "video_name": video_name,
            "status": "ok",
            "error": None,
            "skipped": False,
            "duration_sec": 0,
            "processing_time_sec": 0,
            "speed_ratio": 0,
            "rallies": 0,
            "output_dir": "",
        }

        # 断点续跑：跳过已有输出
        if _output_exists(video_path):
            result["skipped"] = True
            result["output_dir"] = os.path.join("outputs", video_name)
            results.append(result)
            if progress_callback:
                progress_callback(idx, total, video_name)
            continue

        try:
            if progress_callback:
                progress_callback(idx, total, video_name)

            system = BadmintonAnalysisSystem(
                video_path,
                template_path=template_path,
                **system_kwargs,
            )
            system.keep_audio = keep_audio
            system.process_video()

            # 处理耗时
            if system.end_time and system.start_time:
                result["processing_time_sec"] = round(
                    system.end_time - system.start_time, 2
                )

            result["rallies"] = system.rally_count
            result["output_dir"] = system.save_dir

            # 位置可视化
            if visualize_positions:
                vis_dir = os.path.join(system.save_dir, "position_visualizations")
                try:
                    analyze_player_positions(
                        system.detections_path, vis_dir, fps=system.fps
                    )
                except Exception:
                    pass  # 可视化失败不影响主流程

            # 获取视频真实时长，计算处理速度比
            dur = _get_video_duration(video_path)
            result["duration_sec"] = dur
            if dur > 0 and result["processing_time_sec"] > 0:
                result["speed_ratio"] = round(result["processing_time_sec"] / dur, 2)

        except Exception as exc:
            result["status"] = "error"
            result["error"] = str(exc)

        results.append(result)

    batch_end = time.time()

    summary = {
        "batch_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "batch_duration_sec": round(batch_end - batch_start, 2),
        "total_videos": total,
        "completed": sum(1 for r in results if r["status"] == "ok" and not r["skipped"]),
        "skipped": sum(1 for r in results if r["skipped"]),
        "failed": sum(1 for r in results if r["status"] == "error"),
        "results": results,
    }

    return summary


def generate_summary(summary: dict, output_dir: str | None = None) -> str:
    """将汇总结果写入 batch_summary.json 并返回路径。

    Args:
        summary: batch_analyze() 的返回值。
        output_dir: 输出目录，默认为当前目录。

    Returns:
        JSON 文件的路径。
    """
    out_dir = output_dir or "."
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "batch_summary.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    return path


def generate_html_report(summary: dict, output_dir: str | None = None) -> str:
    """生成批处理汇总 HTML 报告。

    Args:
        summary: batch_analyze() 的返回值。
        output_dir: 输出目录，默认为当前目录。

    Returns:
        HTML 文件的路径。
    """
    out_dir = output_dir or "."
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "batch_report.html")

    rows_html = ""
    for r in summary["results"]:
        status_icon = {
            "ok": "✅",
            "error": "❌",
        }.get(r["status"] if not r["skipped"] else "skipped", "⏭️")
        if r["skipped"]:
            status_icon = "⏭️"
            status_text = "已跳过（已有输出）"
        elif r["status"] == "ok":
            status_text = "完成"
        else:
            status_text = f"失败: {r['error']}"

        rows_html += f"""<tr>
            <td>{status_icon}</td>
            <td>{r['video_name']}</td>
            <td>{r['rallies']}</td>
            <td>{r['duration_sec']:.1f}s</td>
            <td>{r['processing_time_sec']:.1f}s</td>
            <td>{r['speed_ratio']}x</td>
            <td>{status_text}</td>
        </tr>"""

    html = f"""<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <title>批量分析报告 — Good-Badminton</title>
    <style>
        body {{ font-family: 'Microsoft YaHei', sans-serif; background: #1a1a2e; color: #eee;
               max-width: 900px; margin: 40px auto; padding: 20px; }}
        h1 {{ color: #ff6b6b; }}
        .summary {{ background: #16213e; border-radius: 10px; padding: 20px; margin: 20px 0; }}
        .summary span {{ margin-right: 30px; }}
        table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
        th, td {{ padding: 12px 16px; text-align: left; border-bottom: 1px solid #2a2a4a; }}
        th {{ background: #0f3460; }}
        tr:hover {{ background: #1a1a3e; }}
        .footer {{ margin-top: 40px; color: #888; font-size: 0.85em; text-align: center; }}
    </style>
</head>
<body>
    <h1>🏸 Good-Badminton 批量分析报告</h1>
    <div class="summary">
        <span>📅 {summary['batch_time']}</span>
        <span>⏱️ 总耗时: {summary['batch_duration_sec']:.1f}s</span>
        <span>📹 总计: {summary['total_videos']}</span>
        <span>✅ 完成: {summary['completed']}</span>
        <span>⏭️ 跳过: {summary['skipped']}</span>
        <span>❌ 失败: {summary['failed']}</span>
    </div>
    <table>
        <thead>
            <tr>
                <th>状态</th><th>视频</th><th>回合数</th>
                <th>视频时长</th><th>处理耗时</th><th>速度比</th><th>备注</th>
            </tr>
        </thead>
        <tbody>
            {rows_html}
        </tbody>
    </table>
    <div class="footer">Generated by Good-Badminton Batch Analyzer</div>
</body>
</html>"""

    with open(path, "w", encoding="utf-8") as f:
        f.write(html)

    return path


def _str_to_bool(value):
    """将字符串 'true'/'false' 转为布尔值，其他类型原样返回。"""
    if isinstance(value, str):
        return value.lower() == "true"
    return value


def _get_video_duration(video_path: str) -> float:
    """获取视频时长（秒），失败返回0。"""
    try:
        import cv2

        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return 0
        fps = cap.get(cv2.CAP_PROP_FPS)
        frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        cap.release()
        return frames / fps if fps > 0 else 0
    except Exception:
        return 0
