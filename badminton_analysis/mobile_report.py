"""Build mobile-app friendly summaries from Good-Badminton outputs."""

from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path
from typing import Any

from .movement_metrics import summarize_detections as summarize_stable_detections


ADVICE_KNOWLEDGE_PATH = Path(__file__).with_name("advice_knowledge.json")


def load_json(path: str | os.PathLike[str] | None) -> dict[str, Any]:
    if not path or not os.path.isfile(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


@lru_cache(maxsize=1)
def load_advice_knowledge() -> dict[str, Any]:
    data = load_json(ADVICE_KNOWLEDGE_PATH)
    return {
        "sources": data.get("sources") or [],
        "entries": data.get("entries") or [],
    }


def summarize_detections(detections_path: str | os.PathLike[str] | None) -> dict[str, Any]:
    """Calculate stable movement metrics from detections.jsonl."""
    return summarize_stable_detections(detections_path)


def build_mobile_report(
    *,
    result: dict[str, Any],
    metadata_path: str | os.PathLike[str] | None = None,
    detections_path: str | os.PathLike[str] | None = None,
) -> dict[str, Any]:
    metadata_path = str(metadata_path or result.get("metadata") or "")
    detections_path = str(detections_path or result.get("detections") or "")
    metadata = load_json(metadata_path)
    detection_summary = summarize_detections(detections_path)

    video = metadata.get("video") or {}
    match = detection_summary["match"]
    coaching = generate_coaching(detection_summary)
    report_summary = generate_report_summary(match)

    return {
        "schema_version": "mobile-report-v1",
        "video": {
            "name": video.get("name"),
            "duration_sec": round(float(video.get("duration_sec") or 0.0), 2),
            "fps": round(float(video.get("fps") or 0.0), 2),
            "width": video.get("width"),
            "height": video.get("height"),
        },
        "summary": {
            "total_distance_m": match["total_distance_m"],
            "primary_player_distance_m": match.get("primary_player_distance_m", 0.0),
            "max_speed_mps": match["max_speed_mps"],
            "raw_max_speed_mps": match.get("raw_max_speed_mps", 0.0),
            "avg_speed_mps": match["avg_speed_mps"],
            "intensity_score": match["intensity_score"],
            "detected_frames": detection_summary["frames_with_detections"],
            "shuttlecock_frames": detection_summary["frames_with_shuttlecock"],
            "active_time_sec": match["active_time_sec"],
            "distance_per_min": match["distance_per_min"],
            "combined_distance_per_min": match.get("combined_distance_per_min", 0.0),
            "coverage_area_m2": match["coverage_area_m2"],
            "court_span_x_m": match["court_span_x_m"],
            "court_span_y_m": match["court_span_y_m"],
            "front_court_ratio": match["front_court_ratio"],
            "back_court_ratio": match["back_court_ratio"],
            "left_court_ratio": match["left_court_ratio"],
            "right_court_ratio": match["right_court_ratio"],
            "high_intensity_moves": match["high_intensity_moves"],
            "shuttlecock_ratio": detection_summary["shuttlecock_ratio"],
            "stable_position_frames": match.get("stable_position_frames", 0),
            "dropped_jump_count": match.get("dropped_jump_count", 0),
            "tracking_quality_score": match.get("tracking_quality_score", 0),
        },
        "report_summary": report_summary,
        "players": detection_summary["players"],
        "coaching": coaching,
        "advice": flatten_coaching_advice(coaching),
        "advice_sources": load_advice_knowledge()["sources"],
        "raw": {
            "metadata": metadata,
        },
    }


def generate_report_summary(match: dict[str, Any]) -> str:
    distance = float(match.get("total_distance_m") or 0.0)
    max_speed = float(match.get("max_speed_mps") or 0.0)
    intensity = int(match.get("intensity_score") or 0)
    coverage = float(match.get("coverage_area_m2") or 0.0)
    active_time = float(match.get("active_time_sec") or 0.0)

    if distance <= 0:
        return "本次视频未检测到稳定移动数据，建议检查拍摄角度或手动校准球场角点。"

    intensity_text = "较高" if intensity >= 70 else "中等" if intensity >= 45 else "偏低"
    speed_text = "爆发移动明显" if max_speed >= 4.5 else "移动节奏较平稳"
    coverage_text = "场地覆盖较完整" if coverage >= 12 else "覆盖范围偏集中"
    if active_time < 25:
        return f"本次片段较短，训练强度{intensity_text}，{speed_text}，可作为快速复盘样例。"
    return f"本次训练强度{intensity_text}，{speed_text}，{coverage_text}。"


def generate_coaching(detection_summary: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    knowledge = load_advice_knowledge()
    entries = {entry.get("id"): entry for entry in knowledge["entries"]}
    coaching: dict[str, list[dict[str, Any]]] = {
        "strengths": [],
        "weaknesses": [],
        "improvements": [],
    }

    match = detection_summary.get("match") or {}
    players = detection_summary.get("players") or []
    distance = float(match.get("total_distance_m") or 0.0)
    max_speed = float(match.get("max_speed_mps") or 0.0)
    raw_max_speed = float(match.get("raw_max_speed_mps") or 0.0)
    avg_speed = float(match.get("avg_speed_mps") or 0.0)
    active_time = float(match.get("active_time_sec") or 0.0)
    distance_per_min = float(match.get("distance_per_min") or 0.0)
    combined_distance_per_min = float(match.get("combined_distance_per_min") or 0.0)
    intensity = int(match.get("intensity_score") or 0)
    coverage_area = float(match.get("coverage_area_m2") or 0.0)
    span_x = float(match.get("court_span_x_m") or 0.0)
    span_y = float(match.get("court_span_y_m") or 0.0)
    front_ratio = float(match.get("front_court_ratio") or 0.0)
    back_ratio = float(match.get("back_court_ratio") or 0.0)
    left_ratio = float(match.get("left_court_ratio") or 0.0)
    right_ratio = float(match.get("right_court_ratio") or 0.0)
    high_intensity_moves = int(match.get("high_intensity_moves") or 0)
    dropped_jump_count = int(match.get("dropped_jump_count") or 0)
    tracking_quality = int(match.get("tracking_quality_score") or 0)
    frames = int(detection_summary.get("frames_with_detections") or 0)
    shuttlecock_ratio = float(detection_summary.get("shuttlecock_ratio") or 0.0)
    zone_bias = max(abs(front_ratio - back_ratio), abs(left_ratio - right_ratio))
    player_gap = player_load_gap(players)

    if distance <= 0 or frames <= 0:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "data_insufficient_weakness",
            "未检测到稳定的球员移动轨迹。",
        )
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "camera_setup_improvement",
            "优先解决拍摄视野或四角点，之后再评估训练表现。",
        )
        return coaching

    if distance_per_min >= 110 or intensity >= 65:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "work_rate_strength",
            (
                f"强度分 {intensity}，单人平均单位时间移动约 {format_metric(distance_per_min, 'm/min')}；"
                f"双人合计移动负荷约 {format_metric(combined_distance_per_min, 'm/min')}。"
            ),
            detail="这段视频的移动密度较高，说明回合中连续启动、追球和攻防转换比较明显。",
            training_focus="后续复盘可以重点观察高强度移动后是否能马上回到合理中区，而不只是看最高速度。",
        )
    if max_speed >= 4.8:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "fast_start_strength",
            (
                f"稳定最高速度 {format_metric(max_speed, 'm/s')}，"
                f"高强度移动样本 {high_intensity_moves} 次。"
            ),
            detail="球员在短距离启动和抢点上有明显表现，说明这段回合不是低强度慢节奏。",
            training_focus="保持分腿垫步后的第一步质量，同时注意启动后不要失去身体重心。",
        )
    if coverage_area >= 10 or span_x >= 3.3 or span_y >= 4.0:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "court_coverage_strength",
            (
                f"覆盖面积约 {format_metric(coverage_area, 'm²')}，横向 {format_metric(span_x, 'm')}、"
                f"纵向 {format_metric(span_y, 'm')}；前后场比例 {format_percent(front_ratio)} / {format_percent(back_ratio)}，"
                f"左右场比例 {format_percent(left_ratio)} / {format_percent(right_ratio)}。"
            ),
            detail="轨迹已经覆盖到较大场地范围，说明回合中存在前后或左右调动。",
            training_focus="结合轨迹图观察是否每次到位后都能回中，避免覆盖范围大但下一拍恢复慢。",
        )
    if frames >= 120 and shuttlecock_ratio >= 0.5 and tracking_quality >= 80:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "stable_data_strength",
            (
                f"有效检测 {frames} 帧，羽毛球识别占比约 {format_percent(shuttlecock_ratio)}，"
                f"轨迹质量分 {tracking_quality}。"
            ),
            detail="画面识别质量可用，本次报告中的热力图、轨迹和集锦有参考价值。",
            training_focus="继续保持固定机位和完整球场画面，方便后续不同训练之间做对比。",
        )
    if player_gap and player_gap["distance_gap_ratio"] <= 0.18 and player_gap["speed_gap_ratio"] <= 0.20:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "balanced_rally_strength",
            (
                f"{player_gap['first_name']} 移动 {format_metric(player_gap['first_distance'], 'm')}，"
                f"{player_gap['second_name']} 移动 {format_metric(player_gap['second_distance'], 'm')}；"
                f"双方距离差约 {format_percent(player_gap['distance_gap_ratio'])}。"
            ),
            detail="双方移动负荷接近，说明这一段对抗参与度比较均衡，适合做攻防节奏复盘。",
            training_focus="对照视频分别观察双方被调动后的回中速度，找出谁在下一拍更早完成站位。",
        )

    if max_speed >= 4.5 and (avg_speed < 1.5 or distance_per_min < 95):
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "low_continuity_weakness",
            f"最高速度 {format_metric(max_speed, 'm/s')}，但平均速度 {format_metric(avg_speed, 'm/s')}，爆发后连续衔接还有提升空间。",
        )
    elif intensity >= 70 and max_speed >= 5.5 and active_time < 30:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "low_continuity_weakness",
            (
                f"稳定最高速度 {format_metric(max_speed, 'm/s')}，平均速度 {format_metric(avg_speed, 'm/s')}，"
                f"高强度移动 {high_intensity_moves} 次。"
            ),
            title="高强度后的回中质量需复核",
            detail="指标显示这段回合强度很高，但短片段无法直接判断连续多拍后的恢复质量，需要结合视频看每次冲刺后是否及时回中。",
            training_focus="复盘时重点看高强度启动后的第一步恢复：击球后重心是否稳定、是否能立刻回到合理中区。",
        )
    if coverage_area < 8 and active_time >= 8:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "narrow_coverage_weakness",
            f"轨迹覆盖约 {format_metric(coverage_area, 'm²')}，可能集中在局部区域。",
        )
    if intensity < 45 and distance_per_min < 95:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "low_intensity_weakness",
            (
                f"强度分 {intensity}，单位时间移动约 {format_metric(distance_per_min, 'm/min')}，"
                f"稳定最高速度 {format_metric(max_speed, 'm/s')}。"
            ),
            detail="这段片段的移动密度和速度都偏低，更像低负荷练习或非对抗片段。",
            training_focus="先提高连续移动密度，再比较技术细节；正式复盘建议选连续对抗片段。",
        )
    elif active_time < 25:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "short_sample_weakness",
            (
                f"有效分析时长约 {format_metric(active_time, 's')}，但强度分 {intensity}；"
                "它适合评价这一回合，不适合代表整场训练。"
            ),
            detail="当前片段强度不低，问题不是训练轻，而是样本时间短，结论更偏向单回合复盘。",
            training_focus="当前结果只代表这一回合，复盘时重点观察启动、到位和回中衔接。",
        )
    if zone_bias >= 0.35 and coverage_area >= 8:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "movement_balance_weakness",
            (
                f"前后场比例 {format_percent(front_ratio)} / {format_percent(back_ratio)}，"
                f"左右场比例 {format_percent(left_ratio)} / {format_percent(right_ratio)}。"
            ),
            detail="移动分布存在明显偏向，可能是该回合战术集中，也可能暴露出某个区域覆盖不足。",
            training_focus="先结合视频画面判断对手是否持续压同一区域；若不是战术导致，再补相反区域的启动和回中。",
        )
    if player_gap and player_gap["distance_gap_ratio"] >= 0.28:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "player_load_gap_weakness",
            (
                f"{player_gap['first_name']} 移动 {format_metric(player_gap['first_distance'], 'm')}，"
                f"{player_gap['second_name']} 移动 {format_metric(player_gap['second_distance'], 'm')}；"
                f"距离差约 {format_percent(player_gap['distance_gap_ratio'])}。"
            ),
            detail="双方移动负荷差异较大，可能是一方被持续调动，也可能是某一侧跟踪质量不稳定。",
            training_focus="结合视频确认是哪一方承担了更多被动移动，再看对应球员的回中和补位是否慢半拍。",
        )
    if shuttlecock_ratio < 0.45 and frames >= 60:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "low_shuttle_visibility_weakness",
            f"羽毛球识别占比约 {round(shuttlecock_ratio * 100)}%，球速和集锦判断会更不稳定。",
        )
    if tracking_quality and (
        tracking_quality < 80
        or dropped_jump_count >= 80
        or (raw_max_speed >= max(max_speed * 2.2, 10.0) and dropped_jump_count >= 20)
    ):
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "tracking_noise_weakness",
            (
                f"轨迹质量分 {tracking_quality}，过滤跳点 {dropped_jump_count} 个；"
                f"原始峰值 {format_metric(raw_max_speed, 'm/s')}，稳定峰值 {format_metric(max_speed, 'm/s')}。"
            ),
            detail="报告已经使用稳定速度，但原始轨迹里仍有跳点，说明部分脚点或关键点存在抖动。",
            training_focus="优先检查画面是否完整、角点是否贴合外线、球员脚部是否被遮挡。",
        )

    if not coaching["strengths"]:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "stable_data_strength",
            f"已生成 {frames} 帧有效轨迹，可结合热力图做基础复盘。",
        )
    if not coaching["weaknesses"]:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "movement_balance_weakness",
            "本次没有明显异常短板，下一阶段建议重点观察击球后回中是否稳定。",
            title="下一阶段观察回中质量",
            detail="数据上没有明显短板，比赛片段更适合继续看细节：到位后重心是否稳定、击球后是否及时回中。",
            training_focus="复盘视频时逐拍暂停，观察每次击球后的第一步恢复方向和回中速度。",
        )

    if has_item(coaching["weaknesses"], "low_continuity_weakness") or max_speed >= 4.8:
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "split_step_recovery_drill",
            "把爆发启动转化成连续回合能力。",
            detail="高强度片段里，真正影响下一拍的是启动后的回位质量。",
            training_focus="六点影子步每次到点后必须回中，30 秒训练、30 秒休息，4 组；不要只追求第一步快。",
        )
    if has_item(coaching["weaknesses"], "movement_balance_weakness"):
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "balanced_coverage_drill",
            "根据前后场或左右场比例偏向，补齐相反区域的启动和回中。",
        )
    if intensity < 60 or distance_per_min < 120:
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "multi_directional_drill",
            "提高连续多拍下的移动质量。",
        )
    if coverage_area >= 8 and max_speed >= 4.5:
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "rear_court_recovery_drill",
            "高强度调动后重点保证后场到中区的恢复。",
        )
    if has_item(coaching["weaknesses"], "narrow_coverage_weakness"):
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "coverage_shadow_drill",
            "用于补齐前后场和左右两侧覆盖。",
        )
    if has_item(coaching["weaknesses"], "short_sample_weakness"):
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "longer_sample_review",
            f"当前有效时长 {format_metric(active_time, 's')}，更适合单回合复盘；连续训练建议补充更长片段。",
            detail="短片段已经能看出启动和回中问题，但强度趋势、覆盖习惯和体能负荷需要更长样本。",
            training_focus="同一机位连续拍摄 30-90 秒，保留完整球场；每次复盘对比强度分、稳定速度、覆盖面积和回中质量。",
        )
    if has_item(coaching["weaknesses"], "low_shuttle_visibility_weakness"):
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "camera_setup_improvement",
            "先提升视频质量，再对球速和击球片段做判断。",
        )
    if has_item(coaching["weaknesses"], "tracking_noise_weakness"):
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "camera_setup_improvement",
            "先减少轨迹跳点，再比较速度、距离和集锦。",
        )
    if len(coaching["improvements"]) < 2:
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "net_lunge_drill",
            "补充网前低重心和回收能力。",
        )

    coaching["strengths"] = coaching["strengths"][:3]
    coaching["weaknesses"] = coaching["weaknesses"][:3]
    coaching["improvements"] = coaching["improvements"][:3]
    return coaching


def add_coaching_item(
    coaching: dict[str, list[dict[str, Any]]],
    group: str,
    entries: dict[str, dict[str, Any]],
    entry_id: str,
    basis: str,
    *,
    title: str | None = None,
    detail: str | None = None,
    training_focus: str | None = None,
) -> None:
    if has_item(coaching[group], entry_id):
        return
    entry = entries.get(entry_id)
    if not entry:
        return
    coaching[group].append(
        {
            "id": entry_id,
            "title": title or entry.get("title") or entry_id,
            "detail": detail or entry.get("principle") or "",
            "basis": basis,
            "training_focus": training_focus if training_focus is not None else entry.get("training_focus") or "",
            "source_ids": entry.get("source_ids") or [],
        }
    )


def has_item(items: list[dict[str, Any]], entry_id: str) -> bool:
    return any(item.get("id") == entry_id for item in items)


def flatten_coaching_advice(coaching: dict[str, list[dict[str, Any]]]) -> list[str]:
    labels = {
        "strengths": "当前优点",
        "weaknesses": "目前缺点",
        "improvements": "改进建议",
    }
    flattened: list[str] = []
    for group in ("strengths", "weaknesses", "improvements"):
        for item in coaching.get(group, []):
            pieces = [item.get("detail") or "", item.get("training_focus") or ""]
            text = " ".join(piece for piece in pieces if piece).strip()
            flattened.append(f"{labels[group]}：{item.get('title', '')}。{text}")
    return flattened


def format_metric(value: float, unit: str) -> str:
    if abs(value) >= 100:
        text = f"{value:.0f}"
    else:
        text = f"{value:.2f}".rstrip("0").rstrip(".")
    return f"{text} {unit}"


def format_percent(value: float) -> str:
    return f"{round(max(0.0, min(float(value), 1.0)) * 100)}%"


def player_load_gap(players: Any) -> dict[str, Any] | None:
    if not isinstance(players, list) or len(players) < 2:
        return None
    first = players[0] if isinstance(players[0], dict) else {}
    second = players[1] if isinstance(players[1], dict) else {}
    first_distance = float(first.get("total_distance_m") or 0.0)
    second_distance = float(second.get("total_distance_m") or 0.0)
    first_speed = float(first.get("max_speed_mps") or 0.0)
    second_speed = float(second.get("max_speed_mps") or 0.0)
    max_distance = max(first_distance, second_distance)
    max_speed = max(first_speed, second_speed)
    if max_distance <= 0:
        return None
    return {
        "first_name": str(first.get("name") or "球员 A"),
        "second_name": str(second.get("name") or "球员 B"),
        "first_distance": first_distance,
        "second_distance": second_distance,
        "first_speed": first_speed,
        "second_speed": second_speed,
        "distance_gap_ratio": abs(first_distance - second_distance) / max_distance,
        "speed_gap_ratio": abs(first_speed - second_speed) / max_speed if max_speed > 0 else 0.0,
    }


def _empty_match_summary() -> dict[str, Any]:
    return {
        "total_distance_m": 0.0,
        "primary_player_distance_m": 0.0,
        "max_speed_mps": 0.0,
        "raw_max_speed_mps": 0.0,
        "avg_speed_mps": 0.0,
        "active_time_sec": 0.0,
        "distance_per_min": 0.0,
        "combined_distance_per_min": 0.0,
        "coverage_area_m2": 0.0,
        "court_span_x_m": 0.0,
        "court_span_y_m": 0.0,
        "front_court_ratio": 0.0,
        "back_court_ratio": 0.0,
        "left_court_ratio": 0.0,
        "right_court_ratio": 0.0,
        "high_intensity_moves": 0,
        "stable_position_frames": 0,
        "dropped_jump_count": 0,
        "tracking_quality_score": 0,
        "frames_with_detections": 0,
        "frames_with_shuttlecock": 0,
        "shuttlecock_ratio": 0.0,
        "intensity_score": 0,
    }
