# Good-Badminton 使用 Codemagic 打包 iOS 详细流程

本文记录 Good-Badminton Flutter App 从 GitHub 接入 Codemagic、完成无签名
iOS 编译，以及后续配置 Apple Developer、自动签名和 TestFlight 的完整流程。

> Codemagic 有时会被误写成 “MagicCode”。本文统一使用其正式名称
> **Codemagic**。

## 1. 当前项目信息

| 项目 | 当前值 |
| --- | --- |
| GitHub 仓库 | `rundon0401-hue/Good-Badminton-1` |
| 仓库可见性 | Private |
| 默认分支 | `main` |
| Flutter 项目目录 | `frontend_flutter` |
| iOS Bundle ID | `com.rundon0401.goodbadminton` |
| Codemagic 配置文件 | 仓库根目录 `codemagic.yaml` |
| Codemagic Workflow ID | `ios-unsigned` |
| Workflow 名称 | `iOS unsigned verification` |
| 构建机器 | `mac_mini_m2` |
| 当前构建类型 | Release、无签名 |

当前已经成功完成一次无签名 iOS 构建：

- 构建页面：
  [Codemagic Build 6a4a2b1d53d380eb41607711](https://codemagic.io/app/6a4a239c979222bb97c72f6e/build/6a4a2b1d53d380eb41607711)
- `flutter pub get`：通过
- `flutter analyze`：通过
- `flutter test`：通过
- `flutter build ios --release --no-codesign`：通过

## 2. 整体流程

```text
Windows 开发 Flutter
        ↓
推送代码到 GitHub
        ↓
Codemagic 读取 codemagic.yaml
        ↓
macOS 云构建机编译 iOS
        ↓
无签名构建验证
        ↓
开通 Apple Developer
        ↓
App Store Connect API Key
        ↓
Codemagic 自动签名
        ↓
生成 IPA 并上传 App Store Connect
        ↓
TestFlight 安装测试
```

## 3. 准备 GitHub 仓库

Codemagic 每次构建都会重新拉取所选分支在构建开始时的最新提交。已经开始或
已经完成的构建不会自动包含之后提交的代码。

开发完成后执行：

```powershell
cd C:\Users\lanld\Good-Badminton

git status
git add <本次需要提交的文件>
git commit -m "描述本次修改"
git push origin main
```

确认远程仓库已经出现最新提交后，再在 Codemagic 启动构建。

注意：

- 不要使用 `git add .` 盲目提交本地视频、构建缓存或运行结果。
- Flutter 的 `build/`、`.dart_tool/` 不应上传。
- APK 和模型权重通过 GitHub Release 分发，不进入普通 Git 历史。
- 私有仓库需要授权 Codemagic GitHub App 才能拉取代码。

## 4. 生成 iOS 工程

项目最初只有 Android 工程，因此先在 `frontend_flutter` 中生成 iOS 平台文件：

```powershell
cd C:\Users\lanld\Good-Badminton\frontend_flutter

flutter create . --platforms=ios --org com.rundon0401
flutter pub get
```

生成后应包含：

```text
frontend_flutter/ios/
├── Flutter/
├── Runner/
├── Runner.xcodeproj/
├── Runner.xcworkspace/
└── RunnerTests/
```

### 4.1 配置 Bundle ID

文件：

```text
frontend_flutter/ios/Runner.xcodeproj/project.pbxproj
```

Runner 使用：

```text
com.rundon0401.goodbadminton
```

RunnerTests 使用：

```text
com.rundon0401.goodbadminton.RunnerTests
```

后续在 Apple Developer 和 App Store Connect 中必须使用完全一致的 Bundle ID。

### 4.2 配置相册权限

文件：

```text
frontend_flutter/ios/Runner/Info.plist
```

添加：

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>用于选择羽毛球比赛视频进行分析。</string>
```

App 显示名称设置为：

```xml
<key>CFBundleDisplayName</key>
<string>Good-Badminton</string>
```

修改后提交：

```powershell
cd C:\Users\lanld\Good-Badminton

git add frontend_flutter/ios
git commit -m "Add iOS project"
git push origin main
```

## 5. Codemagic 注册与连接 GitHub

1. 打开 [Codemagic](https://codemagic.io/start/)。
2. 使用 GitHub 注册或登录。
3. 进入 `Applications`。
4. 点击 `Add application`。
5. Git provider 选择 `GitHub`。
6. 点击 `Authorize integration`。
7. 在 GitHub 中安装 Codemagic CI/CD GitHub App。
8. 账号选择 `rundon0401-hue`。
9. 建议选择 `Only select repositories`。
10. 只授权 `Good-Badminton-1`。
11. 返回 Codemagic，选择仓库 `Good-Badminton-1`。
12. Project type 选择 `Flutter`。
13. 完成 Add application。

如果仓库没有出现在列表中：

- 检查 Codemagic GitHub App 是否获得该私有仓库权限。
- 如果仓库转移到 GitHub Organization，需要重新给 Organization 安装并授权
  Codemagic GitHub App。

## 6. 使用 YAML 配置

本项目使用仓库根目录的：

```text
codemagic.yaml
```

当前内容：

```yaml
workflows:
  ios-unsigned:
    name: iOS unsigned verification
    instance_type: mac_mini_m2
    max_build_duration: 60

    working_directory: frontend_flutter

    environment:
      flutter: stable
      xcode: latest
      cocoapods: default

    cache:
      cache_paths:
        - $FLUTTER_ROOT/.pub-cache
        - $HOME/Library/Caches/CocoaPods

    scripts:
      - name: Flutter packages
        script: flutter pub get

      - name: Analyze
        script: flutter analyze

      - name: Run tests
        script: flutter test

      - name: Build unsigned iOS app
        script: flutter build ios --release --no-codesign

    artifacts:
      - $CM_BUILD_DIR/frontend_flutter/build/ios/iphoneos/*.app
      - $HOME/Library/Developer/Xcode/DerivedData/**/Build/**/*.log
```

在 Codemagic App 设置页：

1. 点击 `Switch to YAML configuration`。
2. Branch 选择 `main`。
3. 确认页面显示仓库中的 `codemagic.yaml`。
4. 页面出现 `Switch to Workflow Editor` 时，说明当前已经处于 YAML 模式。
5. 可以点击刷新按钮重新从 GitHub 获取配置。

`working_directory: frontend_flutter` 很重要，因为 Flutter 项目不在仓库根目录。

## 7. 第一次无签名 iOS 构建

在 Codemagic 点击 `Start new build`：

```text
Build branch：main
File workflow：iOS unsigned verification
SSH/VNC：关闭
```

然后点击 `Start new build`。

预期按顺序执行：

1. Preparing build machine
2. Fetching app sources
3. Restoring cache
4. Installing SDKs
5. Flutter packages
6. Analyze
7. Run tests
8. Build unsigned iOS app
9. Publishing
10. Cleaning up

成功时页面显示绿色状态，Artifacts 中可以看到无签名 `.app`。

### 无签名构建的限制

无签名构建只用于验证：

- Flutter 代码能够在 macOS/Xcode 环境编译。
- iOS 插件和 CocoaPods/Swift Package 依赖正常。
- 静态检查和自动化测试正常。

它不能：

- 直接安装到普通 iPhone。
- 生成可上传 TestFlight 的正式 IPA。
- 上传 App Store Connect。
- 代替 Apple Developer 会员和代码签名。

## 8. 没有 Mac 时如何测试

没有 Mac 仍然可以通过 Codemagic 完成 iOS 编译和发布：

```text
Codemagic 云端 Mac
        ↓
自动代码签名
        ↓
生成 IPA
        ↓
上传 TestFlight
        ↓
iPhone 安装测试
```

限制：

- 无法像本地 Xcode 一样交互操作 iOS Simulator。
- 可以在 Codemagic 中运行单元测试、Widget 测试和自动化集成测试。
- 真机测试推荐通过 TestFlight。

## 9. Apple Developer 注册

无签名构建不要求 Apple Developer 会员，但 TestFlight 和 App Store 发布必须开通。

注册地址：

[Apple Developer Program](https://developer.apple.com/programs/enroll/)

个人开发者通常选择 `Individual`：

- 需要开启双重认证的 Apple Account。
- 使用真实法定姓名、电话和地址。
- App Store 卖家名称将显示个人法定姓名。
- Apple Developer Program 年费通常为 99 美元或当地等值价格。

Organization 还需要合法实体、D-U-N-S 编号、企业域名邮箱和公开网站。

身份验证、协议接受和付费必须由账号本人完成。

## 10. App Store Connect 创建 App

会员开通后：

1. 登录 [App Store Connect](https://appstoreconnect.apple.com/)。
2. 进入 `Apps`。
3. 点击 `+`。
4. 选择 `New App`。
5. Platform 选择 iOS。
6. Name 填写 `Good-Badminton`。
7. Primary Language 选择简体中文。
8. Bundle ID 选择 `com.rundon0401.goodbadminton`。
9. SKU 可填写 `good-badminton-ios-001`。
10. User Access 根据实际需求选择。
11. 点击 Create。

Bundle ID 必须与 Flutter iOS 工程一致。

## 11. 创建 App Store Connect API Key

建议为 Codemagic 单独创建 API Key：

1. App Store Connect → `Users and Access`。
2. 进入 `Integrations`。
3. 选择 `App Store Connect API`。
4. 必要时由 Account Holder 先申请 API 访问权限。
5. 创建 Team Key。
6. 名称可填写 `Codemagic CI`。
7. Role 建议选择 `App Manager`。
8. 记录 Issuer ID。
9. 记录 Key ID。
10. 下载 `.p8` 私钥。

安全要求：

- `.p8` 只能下载一次。
- 不要提交到 GitHub。
- 不要放进 Flutter App。
- 不要通过聊天工具公开发送。
- 如果怀疑泄露，立即在 App Store Connect 撤销。

## 12. Codemagic 自动签名

在 Codemagic Team/Account Settings：

1. 打开 `Integrations`。
2. 找到 Apple Developer Portal。
3. 点击 Connect。
4. 输入 Issuer ID。
5. 输入 Key ID。
6. 直接上传 `.p8`。
7. 保存。

然后在 App 设置中启用 Automatic code signing，并选择：

```text
Bundle ID：com.rundon0401.goodbadminton
Profile type：App Store
```

Codemagic 会创建或获取匹配的 Distribution Certificate 和 Provisioning Profile。

## 13. 发布到 TestFlight

签名工作流需要将无签名命令替换为签名 IPA 构建，并加入 App Store Connect
publishing 配置。配置 API Key 前不要提前提交真实密钥到 YAML。

发布成功后的流程：

```text
Codemagic 生成 IPA
        ↓
上传 App Store Connect
        ↓
Apple Processing
        ↓
TestFlight 出现构建版本
        ↓
添加测试人员
        ↓
iPhone 安装 TestFlight
        ↓
安装 Good-Badminton
```

Apple 处理构建可能需要数分钟或更久。若 Codemagic 已上传成功但 TestFlight
暂时看不到，先检查 App Store Connect 的构建处理状态和 Apple 邮件。

## 14. 后端地址与 iOS 网络限制

当前开发阶段 Flutter App 可能使用局域网 HTTP 地址，例如：

```text
http://172.29.11.85:8001
```

注意：

- 手机必须与后端电脑处于同一网络。
- 电脑 IP 改变后，旧构建不会自动更新。
- iOS 默认限制明文 HTTP。
- TestFlight 或正式发布建议使用稳定的 HTTPS 后端地址。
- 最好使用编译环境变量区分开发、测试和生产环境，不要长期写死局域网 IP。

推荐后续改造成：

```bash
flutter build ios \
  --dart-define=API_BASE_URL=https://api.example.com
```

## 15. GitHub 更新后如何重新打包

GitHub 更新不会改变已经完成的构建。

手动构建：

1. 推送最新代码到 `main`。
2. 打开 Codemagic。
3. 点击 `Start new build`。
4. Branch 选择 `main`。
5. Workflow 选择需要的工作流。
6. 启动构建。

自动构建：

- 在 Codemagic 配置 GitHub push webhook。
- 设置仅在 `main` 分支更新时自动构建。
- 建议签名和发布流程稳定后再开启自动发布。

## 16. 常见问题

### Codemagic 找不到仓库

检查 GitHub App 是否授权私有仓库。如果仓库属于 Organization，需要在该
Organization 中重新安装 Codemagic GitHub App。

### Codemagic 找不到 Flutter 项目

确认 YAML 中存在：

```yaml
working_directory: frontend_flutter
```

### 找不到 codemagic.yaml

确认文件位于 GitHub 仓库根目录，而不是 `frontend_flutter` 内部，并且已经
推送到当前构建分支。

### iOS 构建提示签名错误

无签名验证工作流必须使用：

```bash
flutter build ios --release --no-codesign
```

签名构建则必须配置 Apple Developer、Bundle ID、证书和 Provisioning Profile。

### TestFlight 无法连接后端

检查：

- App 中的 `baseUrl`。
- 是否使用 HTTPS。
- 后端是否公网可访问。
- 防火墙和端口是否开放。
- 报告媒体相对路径是否正确拼接到 `baseUrl`。

### 已完成构建没有包含最新代码

Codemagic 构建使用启动构建时选定提交的快照。推送新代码后必须重新构建。

## 17. 官方文档

- [Codemagic 添加应用](https://docs.codemagic.io/getting-started/adding-apps/)
- [Codemagic iOS 自动签名](https://docs.codemagic.io/flutter-code-signing/ios-code-signing/)
- [Codemagic 发布 App Store Connect](https://docs.codemagic.io/yaml-publishing/app-store-connect/)
- [Apple Developer Program 注册](https://developer.apple.com/programs/enroll/)
- [App Store Connect 创建 App](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [App Store Connect API Key](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)

