# Good-Badminton AI 羽毛球训练复盘 App

当前版本是比赛/移动端闭环版本：Android Flutter App + Windows FastAPI 后端 + Good-Badminton 算法 + Cloudflare 临时公网访问。

## 当前稳定能力

- Android App 名称：`AI羽毛球`
- 唯一比赛后端：`backend_api.py`
- 默认后端端口：`8001`
- 支持同 WiFi 和 Cloudflare Tunnel 公网 HTTPS
- 支持游客模式 `user_id`
- 支持视频上传、任务轮询、历史记录、删除历史
- 支持自动检测角点并标注；如果不贴合真实边线，可以手动校正四角点
- 支持训练报告、核心指标、进阶指标、热力图、轨迹图、精彩集锦、集锦入选理由、训练建议
- App 对公网短暂断连会自动重试，重试提示为绿色进行中状态

## 主要文件

| 路径 | 作用 |
| --- | --- |
| `backend_api.py` | 比赛/移动端 FastAPI 后端 |
| `mobile_app/` | Flutter Android/iOS App |
| `badminton_analysis/` | 核心分析、报告、集锦、训练建议 |
| `webui/pipeline.py` | 后端调用的分析管线 |
| `start_mobile_backend.bat` | 只启动 `backend_api.py:8001` |
| `start_public_tunnel.bat` | 只启动 Cloudflare Tunnel 到 `127.0.0.1:8001` |
| `start_mobile_public.bat` | 一键检查/启动后端并启动公网隧道 |

旧网页/Gradio 演示启动脚本已经删除，避免和移动端后端混淆。

## 运行方式

### 公网/手机测试

双击或运行：

```bat
D:\py\Good-Badminton\start_mobile_public.bat
```

它会打开两个窗口：

- `Good-Badminton Mobile Backend 8001`
- `Good-Badminton Public HTTPS Tunnel`

在 Tunnel 窗口复制：

```text
https://xxxx.trycloudflare.com
```

App 的“后端地址”只填这个根地址，不要加 `/docs` 或 `/api`。

### 同 WiFi 测试

只启动后端：

```bat
D:\py\Good-Badminton\start_mobile_backend.bat
```

App 后端地址填写电脑 WLAN IPv4：

```text
http://172.29.72.218:8001
```

### Swagger 测试

```text
http://127.0.0.1:8001/docs
http://<电脑IP>:8001/docs
https://xxxx.trycloudflare.com/docs
```

## App 安装

当前 debug APK：

```text
D:\py\Good-Badminton\mobile_app\build\app\outputs\flutter-apk\app-debug.apk
```

USB 安装：

```bat
C:\Users\jiale\AppData\Local\Android\Sdk\platform-tools\adb.exe install -r D:\py\Good-Badminton\mobile_app\build\app\outputs\flutter-apk\app-debug.apk
```

也可以把 APK 发到手机，直接安装覆盖旧版。

## 核心 API 摘要

Base URL 示例：

```text
http://172.29.72.218:8001
https://xxxx.trycloudflare.com
```

接口：

```text
GET    /api/health
POST   /api/users/register
GET    /api/users/{user_id}
PATCH  /api/users/{user_id}
POST   /api/videos/preview-frame
POST   /api/videos/upload
GET    /api/tasks
GET    /api/history?user_id=xxx&limit=30
GET    /api/tasks/{task_id}
GET    /api/tasks/{task_id}/report
GET    /api/tasks/{task_id}/highlight
DELETE /api/tasks/{task_id}?user_id=xxx
GET    /api/demo/sample
```

前端只需要更换 Base URL，接口路径不变。

### 注册 ID 唯一性

当前 App 仍然兼容游客模式；如果前端要做“注册 ID 不能重复”，调用这个接口：

```http
POST /api/users/register
Content-Type: application/json

{
  "user_id": "jiale01",
  "nickname": "Jiale"
}
```

成功返回：

```json
{
  "user": {
    "user_id": "jiale01",
    "nickname": "Jiale",
    "created_at": 1780000000.0,
    "updated_at": 1780000000.0
  }
}
```

重复注册同一个 ID 返回 `409`：

```json
{
  "detail": {
    "code": "USER_ID_TAKEN",
    "message": "这个用户 ID 已经被注册。",
    "hint": "请换一个 ID，或使用本机已保存的游客身份继续查看历史记录。"
  }
}
```

ID 规则：`3-32` 位，只能使用小写英文字母、数字、下划线 `_` 或短横线 `-`，并且必须以字母或数字开头。注册表临时保存在：

```text
mobile_backend_data/users.json
```

这不是正式账号系统，没有密码和手机号；适合当前比赛阶段的“轻账号/游客档案”。

## 台式机服务器迁移

迁移目标：让台式机长期运行后端，手机 App 和前端只访问一个公网/内网 Base URL。

### 1. 拷贝项目

把整个项目复制到台式机，例如：

```text
D:\py\Good-Badminton
```

不要复制这些运行产物也可以：

```text
outputs/
mobile_backend_data/
mobile_app/build/
__pycache__/
.venv/
```

### 2. 还原 Python 环境

推荐仍然使用 conda 环境名 `badminton`。最低要求：

- Python 环境能运行 `backend_api.py`
- FFmpeg 可用
- 模型权重在 `weights/`
- `D:\tools\cloudflared\cloudflared.exe` 或修改 bat 里的路径

如果台式机路径不同，需要改这三个 bat 里的路径：

```text
start_mobile_backend.bat
start_public_tunnel.bat
start_mobile_public.bat
```

重点变量：

```bat
PROJECT_DIR=项目路径
PYTHON_EXE=conda环境里的python.exe
CLOUDFLARED_EXE=cloudflared.exe路径
PORT=8001
```

### 3. 验证后端

在台式机运行：

```bat
start_mobile_backend.bat
```

浏览器打开：

```text
http://127.0.0.1:8001/api/health
```

### 4. 配公网

临时演示继续用：

```bat
start_mobile_public.bat
```

如果要长期稳定，建议后面换成：

- 固定域名 + HTTPS
- 或 Cloudflare 正式 tunnel 配置
- 或学校/实验室服务器公网 IP + 反向代理

固定域名不能只靠代码完成，需要先有：

- 一个域名，例如 `your-domain.com`
- Cloudflare 账号，并把域名 DNS 接入 Cloudflare
- 台式机服务器能长期运行 `backend_api.py:8001`

准备好以后可以走 Cloudflare Named Tunnel：

```bat
cloudflared tunnel login
cloudflared tunnel create good-badminton
cloudflared tunnel route dns good-badminton api.your-domain.com
cloudflared tunnel run good-badminton
```

模板文件：

```text
deploy/cloudflared-config.example.yml
deploy/start_named_tunnel.example.bat
```

上线后 App 的后端地址固定填写：

```text
https://api.your-domain.com
```

### 5. App 配置

App 不需要重新打包，只要在上传页修改“后端地址”为台式机的新 Base URL。

## 算法现状和改进方向

现在的算法已经能完成闭环，但数据精度还不是“严肃科研级”。主要原因：

1. 球场四角点误差会直接放大到距离、速度、热力图和前后场比例。
2. 球员位置使用检测框/姿态结果映射到球场坐标，脚底点或人体中心点不稳定时会产生跳点。
3. 速度由相邻帧位移除以时间得到，单帧误检会造成异常高速度。
4. 羽毛球速度目前主要用图像像素速度做精彩集锦评分，不是严格的真实 m/s。
5. 短视频样本少，强度、覆盖面积、比例类指标波动较大。

建议不要直接重写算法。下一步应先做“可回退的小步改进”：

### 优先级 A：稳定指标

- 对球员球场坐标做中值滤波或 Savitzky-Golay 平滑。
- 对速度使用滑动窗口速度，不直接相信单帧速度。
- 增加跳点剔除：坐标瞬移、越出球场、单帧来回抖动不计入距离。
- 把 `raw_max_speed_mps` 和稳定后的 `max_speed_mps` 都保留，报告只展示稳定值。

### 优先级 B：角点质量

- 给自动角点增加质量分和低置信度提示。
- 如果自动角点不稳定，强制用户手动校正。
- 手动角点保存到任务里，便于复盘为什么数据不准。

### 优先级 C：集锦选择

- 现在集锦已经综合球速、球员速度、移动距离。
- 后续可以加入“连续多拍”“快速启动后回中”“大范围覆盖”等事件。
- 先输出更清楚的入选理由，再考虑更复杂的动作识别。

### 优先级 D：评测数据集

算法要真正变好，需要建立小型验证集：

- 5-10 个不同拍摄角度的视频
- 每个视频保存人工确认角点
- 人工标注几段“精彩片段”
- 对比自动结果和人工判断

没有验证集就大改算法，容易只是把当前样例调好了，换视频又变差。

## 当前建议

当前版本已经适合比赛演示。下一步最稳的是：

1. 先保留当前 commit 作为稳定点。
2. 用 5-10 个视频做算法问题记录。
3. 单独开分支改“坐标平滑和速度稳定”。
4. 每改一步都用同一批视频回归测试。
