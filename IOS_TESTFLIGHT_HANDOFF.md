# 智羽 iOS TestFlight 交接说明

## 工程信息

- Flutter 工程目录：`frontend_flutter`
- App 名称：`智羽`
- Bundle ID：`com.rundon2026.goodbadminton`
- 最低 iOS 版本：13.0
- 当前版本：0.1.2（Build 2）
- 公网 API：`https://api.audacity6441.kdns.fr`
- 当前 iOS 依赖使用 Flutter Swift Package Manager 配置，不需要补建 Podfile

## 首次 Mac 构建

```bash
cd frontend_flutter
flutter pub get
flutter analyze
flutter test
```

在 Xcode 打开 `ios/Runner.xcworkspace`，选择 Runner Target，确认签名团队为拥有
`com.rundon2026.goodbadminton` 的 Apple Developer Team，并开启自动签名。

如果 App Store Connect 已有 0.1.2 Build 2，下一次 TestFlight 构建必须使用 Build 3：

```bash
flutter build ipa --release \
  --build-name=0.1.2 \
  --build-number=3 \
  --dart-define=API_BASE_URL=https://api.audacity6441.kdns.fr
```

随后可在 Xcode Organizer 或 Transporter 上传 `build/ios/ipa/*.ipa` 到 TestFlight。

## 已包含内容

- Flutter 前端、Android 与 iOS 原生配置
- App 图标、图片、示例视频及 `pubspec.lock`
- `codemagic.yaml` 的无签名与 iOS 模拟器验证工作流
- 后端、数据库迁移、示例球馆服务与测试代码
- 模型权重：`weights/yolo11n-pose.pt`、`weights/yolo11s-ball.pt`

模型权重供 Ubuntu 中心服务器分析使用，不参与 iOS IPA 编译；将它们随仓库交付是为了让服务器可从同一份代码完整恢复。

## 不应提交的签名资料

请不要把 `.p8`、`.mobileprovision`、证书、钥匙串导出文件、Apple ID 密码或 App Store
Connect 密钥提交到仓库。它们应只保存在 Mac 钥匙串或 Codemagic 的加密环境变量中。
