import argparse
import os

from badminton_analysis.batch import batch_analyze, find_videos, generate_summary, generate_html_report
from badminton_analysis.system import BadmintonAnalysisSystem, load_runtime_dependencies



def main():
    parser = argparse.ArgumentParser(description='羽毛球比赛视频分析系统')
    parser.add_argument('--video-path', default='videos/demo.mp4', type=str, help='输入视频文件路径')
    parser.add_argument('--input-dir', default=None, type=str, help='批量模式：分析目录下所有视频文件')
    parser.add_argument('--batch-template', default=None, type=str, help='批量模式共用球场模板图（不提供则逐个弹窗选择）')
    parser.add_argument('--template-path', default='templates/demo.png', type=str, help='球场模板图像路径；不提供时会弹出文件选择框')
    parser.add_argument('--output-dir', default=None, type=str, help='输出目录，默认 outputs/<视频文件名>')
    parser.add_argument('--ball-model', default='weights/yolo11s-ball.pt', type=str, help='YOLO 羽毛球检测模型路径')
    parser.add_argument('--pose-family', default='yolo-pose', choices=['rtmpose', 'rtmo', 'yolo-pose'], help='姿态模型族')
    parser.add_argument('--pose-mode', default='balanced', choices=['lightweight', 'balanced', 'performance'], help='RTMPose / RTMO 模型档位')
    parser.add_argument('--yolo-pose-model', default='weights/yolo11n-pose.pt', type=str, help='YOLO pose 模型路径或模型名')
    parser.add_argument('--pose-roi', choices=['true', 'false'], default='true', help='是否显示姿态检测 ROI 框，默认 true')
    parser.add_argument('--display', choices=['true', 'false'], default='true', help='是否显示视频窗口，默认 true')
    parser.add_argument('--skeletons', choices=['true', 'false'], default='true', help='是否显示人体骨架，默认 true')
    parser.add_argument('--player-trajectories', choices=['true', 'false'], default='true', help='是否显示球员轨迹，默认 true')
    parser.add_argument('--court-trajectory', choices=['true', 'false'], default='true', help='是否显示球场轨迹，默认 true')
    parser.add_argument('--shuttlecock-trajectory', choices=['true', 'false'], default='true', help='是否显示羽毛球轨迹，默认 true')
    parser.add_argument('--player-stats', choices=['true', 'false'], default='true', help='是否显示球员统计信息，默认 true')
    parser.add_argument('--save-images', action='store_true', default=False, help='保存处理后的图像')
    parser.add_argument('--performance-stats', action='store_true', default=True, help='显示性能统计信息')
    parser.add_argument('--visualize-positions', choices=['true', 'false'], default='true', help='是否生成球员位置热力图和散点图，默认 true')
    parser.add_argument('--audio', choices=['true', 'false'], default='true', help='是否保留原视频音频，默认 true')
    parser.add_argument('--language', default='zh', choices=['zh', 'en'], help='选择界面语言 (zh/en)')
    args = parser.parse_args()

    # ── 批量模式 ──────────────────────────────────────────
    if args.input_dir:
        print(f"\n📹 批量模式：扫描目录 {args.input_dir} ...")
        videos = find_videos(args.input_dir)
        if not videos:
            print(f"目录中没有找到视频文件: {args.input_dir}")
            return

        print(f"找到 {len(videos)} 个视频文件")
        for v in videos:
            print(f"  - {os.path.basename(v)}")

        template = args.batch_template or args.template_path

        summary = batch_analyze(
            videos,
            template_path=template,
            language=args.language,
            skeletons=args.skeletons,
            player_trajectories=args.player_trajectories,
            court_trajectory=args.court_trajectory,
            shuttlecock_trajectory=args.shuttlecock_trajectory,
            player_stats=args.player_stats,
            performance_stats=args.performance_stats,
            save_images=args.save_images,
            ball_model=args.ball_model,
            pose_mode=args.pose_mode,
            pose_family=args.pose_family,
            yolo_pose_model=args.yolo_pose_model,
            show_pose_roi=args.pose_roi,
            audio=args.audio,
            visualize_positions=args.visualize_positions == 'true',
        )

        # 生成汇总报告
        out_dir = args.output_dir or "."
        json_path = generate_summary(summary, out_dir)
        html_path = generate_html_report(summary, out_dir)

        print(f"\n{'='*50}")
        print(f"✅ 批量分析完成！")
        print(f"   总计: {summary['total_videos']}  完成: {summary['completed']}"
              f"  跳过: {summary['skipped']}  失败: {summary['failed']}")
        print(f"   汇总 JSON: {json_path}")
        print(f"   HTML 报告: {html_path}")
        print(f"{'='*50}")
        return

    # ── 单视频模式 ────────────────────────────────────────
    load_runtime_dependencies()

    if args.language == 'en':
        from badminton_analysis.visualization.player_positions_en import analyze_player_positions
    else:
        from badminton_analysis.visualization.player_positions_zh import analyze_player_positions

    system = BadmintonAnalysisSystem(
        args.video_path,
        show_display=args.display == 'true',
        show_skeletons=args.skeletons == 'true',
        show_player_trajectories=args.player_trajectories == 'true',
        show_court_trajectory=args.court_trajectory == 'true',
        show_shuttlecock_trajectory=args.shuttlecock_trajectory == 'true',
        show_player_stats=args.player_stats == 'true',
        show_performance_stats=args.performance_stats,
        save_images=args.save_images,
        language=args.language,
        output_dir=args.output_dir,
        ball_model_path=args.ball_model,
        template_path=args.template_path,
        pose_mode=args.pose_mode,
        pose_family=args.pose_family,
        yolo_pose_model=args.yolo_pose_model,
        show_pose_roi=args.pose_roi == 'true'
    )

    system.keep_audio = args.audio == 'true'
    system.process_video()

    if args.visualize_positions == 'true':
        print("\n开始生成球员位置可视化...")
        analyze_player_positions(system.detections_path, os.path.join(system.save_dir, 'position_visualizations'), fps=system.fps)
        print("球员位置可视化完成")

if __name__ == "__main__":
    main()
