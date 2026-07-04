# Good-Badminton 算法精度审计

分支：`analysis/algorithm-metrics-audit`

目标：只分析自动角点、球员移动指标、视频实时标注、报告指标和精彩集锦的可信度问题，不直接破坏当前稳定闭环。

## 当前结论

当前算法已经能完成比赛演示闭环，但指标还不能当作严肃训练量化数据。主要问题不是某一个小 bug，而是“球场映射、球员轨迹、速度统计、报告汇总、视频叠加”之间没有统一的稳定数据层。

最应该先做的是：建立一套统一的“稳定轨迹和指标计算模块”，让视频叠加、报告、热力图、集锦都用同一个数据源。

## 数据链路

当前移动端闭环大致是：

1. App 上传视频，必要时上传手动四角点。
2. `backend_api.py` 创建任务。
3. `webui/pipeline.py` 调用 `BadmintonAnalysisSystem`。
4. `badminton_analysis/court/mapper.py` 把图像坐标映射到 6.1m x 13.4m 球场坐标。
5. `badminton_analysis/visualization/player_pose.py` 用姿态脚踝点估计球员位置。
6. `badminton_analysis/tracking/player.py` 写 `detections.jsonl`，并生成视频叠加的实时移动统计。
7. `badminton_analysis/mobile_report.py` 再读 `detections.jsonl` 生成 App 报告指标。
8. `badminton_analysis/visualization/player_positions_zh.py` 再读 `detections.jsonl` 生成热力图/轨迹图。
9. `badminton_analysis/highlight.py` 再读 `detections.jsonl` 生成精彩集锦。

问题在第 6-9 步：它们都在读同一份轨迹，但指标计算逻辑并不统一。

## 证据

用最近一次输出做只读检查：

`outputs/webui_ae96b5420b9744d5bccf70f33c1020cf_1564_20260704_234651/detections.jsonl`

统计结果：

| 区域 | 有效位置帧 | 缺失帧 | 连续坐标计算最高速度 | 连续坐标 P95 速度 | 写入 payload 的最高速度 |
| --- | ---: | ---: | ---: | ---: | ---: |
| upper | 433 | 105 | 19.82 m/s | 8.72 m/s | 4.06 m/s |
| lower | 538 | 0 | 16.39 m/s | 7.61 m/s | 4.12 m/s |

这说明：

- 原始球场坐标存在明显跳点。
- `detections.jsonl` 里 `players.*.speed` 与用 `players.*.court` 连续坐标重新计算的速度不一致。
- 视频叠加速度、App 报告速度、热力图速度可能展示不同含义的数据。

## 主要问题

### 1. 自动角点不稳定会放大所有后续误差

相关文件：

- `badminton_analysis/court/detector.py`
- `badminton_analysis/court/mapper.py`
- `webui/pipeline.py`

四角点决定透视变换矩阵。只要角点偏一点，球员脚点映射到真实米制坐标就会系统性偏差，距离、速度、覆盖面积、前后场比例、左右场比例都会一起偏。

当前已有 App 手动校正角点，这是正确方向。但算法层还缺：

- 角点置信度。
- 自动角点质量解释。
- 自动角点低质量时强提示用户手动校正。
- 手动角点与自动角点的误差记录。

### 2. 球员位置点容易抖动

相关文件：

- `badminton_analysis/visualization/player_pose.py`
- `badminton_analysis/tracking/player.py`

当前球员位置主要来自双脚踝中点，并向下加 10 像素。问题是：

- 脚踝点被遮挡时容易跳。
- 跳步、转身、跨步时双脚中心不等于身体落点。
- 姿态模型偶发误检会导致单帧位移很大。
- 当前没有轨迹平滑，也没有基于加速度的异常剔除。

### 3. 上下半场身份跟踪太弱

相关文件：

- `badminton_analysis/tracking/player.py`

当前主要按图像 y 坐标和 `mid_height` 划分 `upper/lower`。这适合固定机位单打，但如果检测到多个候选人、影子、裁判、场外人，或者球员靠近中线，就可能发生身份跳变。

后续应至少加入：

- 每半场只保留一个稳定 track。
- 用上一帧球场坐标做最近邻匹配。
- 速度/加速度超过阈值时不要立刻换身份。
- 连续丢失几帧时保留短期预测位置。

### 4. 视频实时指标和报告指标不是同一套算法

相关文件：

- `badminton_analysis/tracking/player.py`
- `badminton_analysis/mobile_report.py`
- `badminton_analysis/visualization/player_positions_zh.py`

当前存在三套逻辑：

- 视频叠加：`PlayerTracker.get_player_movement_stats()`
- App 报告：`mobile_report.summarize_detections()`
- 热力图/轨迹图：`player_positions_zh.py`

它们的采样间隔、最大速度限制、距离累加方式不完全一致，所以用户可能看到：

- 视频上实时速度一个值。
- 报告页最高速度另一个值。
- 轨迹图统计框又是另一个值。

这会削弱比赛展示可信度。

### 5. 速度统计混入了不稳定样本

相关文件：

- `badminton_analysis/mobile_report.py`

报告里既使用 `payload["speed"]`，又根据连续 `court_position` 重新算速度，然后混合进同一个 `speed_samples_mps`。这会让“最高速度”的语义不清楚。

建议改成：

- 原始速度：只用于诊断，不直接展示。
- 稳定速度：由平滑后的轨迹计算，报告和视频都展示它。
- 最高速度：用稳定速度 P95 或 P90，不用单帧最大值。
- 距离：只从稳定轨迹累加，且过滤跳点。

### 6. `image_to_court()` 过早四舍五入

相关文件：

- `badminton_analysis/court/mapper.py`

`image_to_court()` 当前直接 round 到 0.01m。这个精度本身看起来够，但在逐帧速度计算时，过早四舍五入会增加抖动。更合理的是：

- 内部计算保留 float 原值。
- 输出报告/JSON 展示时再 round。

### 7. 精彩集锦评分还不够“运动语义化”

相关文件：

- `badminton_analysis/highlight.py`

当前集锦考虑：

- 羽毛球图像速度，单位是 px/s，不是真实 m/s。
- 球员速度。
- 球员移动距离。

限制：

- 羽毛球速度不是米制速度，受镜头远近影响。
- 短视频小于窗口长度时会接近选整段。
- 集锦依赖当前不稳定的球员速度和坐标。

建议先稳定轨迹和速度，再增强集锦。否则集锦评分会跟着错误指标一起波动。

## 推荐改进路线

### 阶段 0：先做评测，不改算法

建立 5-10 个固定测试视频，每个视频记录：

- 视频时长、分辨率、拍摄角度。
- 自动角点截图。
- 人工确认角点。
- 期望集锦片段。
- 人工主观评价：速度/距离是否明显离谱。

每次改算法都用同一批视频回归。

### 阶段 1：统一指标模块

新增一个独立模块，例如：

`badminton_analysis/movement_metrics.py`

它负责：

- 读取 `detections.jsonl`。
- 输出稳定轨迹。
- 输出统一的距离、速度、覆盖、强度指标。
- 给视频叠加、App 报告、热力图、集锦共同使用。

不要再让多个文件各算一套速度。

### 阶段 2：轨迹平滑和跳点剔除

建议先做保守算法：

- 中值滤波：去掉单帧尖刺。
- 滑动窗口速度：用 0.3-0.5 秒窗口计算速度。
- 最大速度阈值：例如稳定展示值不超过 8-10 m/s。
- 最大加速度阈值：防止一帧来回跳。
- 坐标越界过滤：明显离开球场太远的数据不计入。

输出时保留：

- `raw_max_speed_mps`
- `stable_max_speed_mps`
- `dropped_jump_count`
- `tracking_quality_score`

### 阶段 3：改身份跟踪

先不引入复杂多目标跟踪，做轻量版即可：

- 上半场、下半场各一个 track。
- 候选点按离上一帧稳定位置最近来匹配。
- 如果新点需要超过不合理速度才能到达，则丢弃。
- 丢失 3-5 帧内保留 track，不立即断掉。

### 阶段 4：角点质量评分

自动角点返回：

- `auto_corners`
- `corner_quality_score`
- `corner_quality_reason`
- `manual_recommended`

App 可以显示：“自动识别可能不准，请校正四角点”。

### 阶段 5：集锦再升级

在稳定轨迹基础上，集锦可以增加：

- 高强度移动片段。
- 快速启动片段。
- 大范围覆盖片段。
- 前后场快速切换片段。
- 羽毛球识别稳定时再加入羽毛球速度。

## 建议的下一条开发分支

如果要开始真正改算法，建议新开：

`experiment/movement-metrics-smoothing`

第一批只做：

1. 新增 `movement_metrics.py`。
2. `mobile_report.py` 改用统一指标。
3. 视频叠加暂时不改，先对比新旧报告指标。
4. 用固定测试视频输出对比表。

这样风险最低，不会直接把现有稳定 App 闭环改坏。

