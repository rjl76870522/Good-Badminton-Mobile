# Coaching Advice Knowledge Base

This document explains the structured training advice added after the mobile backend reached the closed-loop demo stage.

## Purpose

The report should not only say one generic sentence. It should give:

1. 当前优点
2. 目前缺点
3. 改进建议

The backend now generates these fields from the current video metrics and a local badminton advice knowledge base.

## Backend Files

| File | Purpose |
| --- | --- |
| `badminton_analysis/advice_knowledge.json` | Local advice knowledge base |
| `badminton_analysis/mobile_report.py` | Selects advice entries from metrics and builds the report |
| `backend_api.py` | Demo report also returns the new structure |

## Report Shape

Frontend should read:

```json
{
  "coaching": {
    "strengths": [
      {
        "title": "爆发启动明显",
        "basis": "检测最高移动速度 6.03 m/s，具备明显爆发移动。",
        "detail": "本次检测到较高峰值移动速度，说明抢点、启动和短距离冲刺能力有表现。",
        "training_focus": "继续保持分腿垫步后再启动的节奏，避免只靠大步硬追导致下一拍回位慢。",
        "source_ids": ["bwf-coach-l1"]
      }
    ],
    "weaknesses": [],
    "improvements": []
  },
  "advice": []
}
```

Use `coaching` for the new UI. `advice` is only a fallback list for old pages.

## Current Rules

The backend currently uses:

| Metric | Used For |
| --- | --- |
| `max_speed_mps` | 判断爆发启动 |
| `avg_speed_mps` | 判断连续移动衔接 |
| `distance_per_min` | 判断单位时间跑动强度 |
| `coverage_area_m2` | 判断场地覆盖范围 |
| `shuttlecock_ratio` | 判断羽毛球识别稳定性 |
| `active_time_sec` | 判断片段是否太短 |

## Knowledge Sources

The first knowledge-base version uses:

| ID | Source |
| --- | --- |
| `bwf-coach-l1` | BWF Coach Education Coaches Manual Level 1 |
| `badmintonskills-footwork-drills` | BadmintonSkills footwork and court coverage drills |

Future additions should be added to `badminton_analysis/advice_knowledge.json` first, then selected in `generate_coaching()`.
