import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum LegalDocumentType {
  privacy,
  agreement,
  personalInformation,
  thirdPartySharing,
  cooperation,
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.type});

  final LegalDocumentType type;

  static const _support = 'https://www.audacity6441.kdns.fr/support';

  @override
  Widget build(BuildContext context) {
    final document = _document(type);
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Text(
              '更新日期：2026年7月21日\n生效日期：2026年7月21日',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            for (final section in document.sections) ...[
              Text(
                section.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(section.body, style: const TextStyle(height: 1.65)),
              const SizedBox(height: 20),
            ],
            if (type == LegalDocumentType.cooperation)
              FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(_support),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('前往支持页面联系'),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _Section = ({String title, String body});
typedef _Document = ({String title, List<_Section> sections});

_Document _document(LegalDocumentType type) {
  return switch (type) {
    LegalDocumentType.privacy => (
        title: '隐私政策',
        sections: [
          (
            title: '一、我们如何提供服务',
            body:
                '智羽用于羽毛球训练视频分析、训练报告查看、合作球馆视频获取和附近场馆查找。部分功能可以离线使用，视频分析需要连接中心服务器。',
          ),
          (
            title: '二、我们处理的信息',
            body:
                '为完成分析，我们会处理匿名用户标识、用户主动上传或从合作球馆选择的视频、手动标记的球场角点、任务状态和分析结果。昵称、头像、签到、护眼模式等偏好默认只保存在本机。使用定位功能时，位置仅用于本次附近场馆搜索，不上传到中心服务器。',
          ),
          (
            title: '三、权限说明',
            body:
                '相机权限用于扫描合作球馆二维码；照片与视频权限用于选择视频、头像和保存分析作品；通知权限用于提示分析完成或失败；定位权限仅在用户主动查找附近场馆时使用。拒绝某项权限不会影响与该权限无关的功能。',
          ),
          (
            title: '四、存储与保护',
            body:
                '分析任务及结果保存在项目自管的中心服务器，用户可以在训练历史中删除对应记录。本机离线报告由用户自行管理。我们采用 HTTPS、Cloudflare Tunnel、访问隔离和数据库备份等措施保护数据，但互联网传输无法保证绝对安全。',
          ),
          (
            title: '五、信息共享',
            body:
                '我们不会出售个人信息。仅在完成网络传输、系统地图跳转、应用分发或法律要求时，按照必要范围使用相关服务。具体情况请查看《第三方信息共享清单》。',
          ),
          (
            title: '六、用户权利与未成年人保护',
            body:
                '用户可以管理系统权限、关闭通知、清除离线报告或删除训练记录。如需进一步查询、更正或删除数据，可通过支持页面联系项目团队。未成年人应在监护人指导下使用本服务，不应上传包含他人敏感信息的视频。',
          ),
          (
            title: '七、联系我们',
            body:
                '运营主体为智羽项目团队。隐私问题、数据删除和投诉建议可通过 https://www.audacity6441.kdns.fr/support 提交。',
          ),
        ],
      ),
    LegalDocumentType.agreement => (
        title: '用户协议',
        sections: [
          (
            title: '一、服务说明',
            body:
                '智羽提供训练视频分析和辅助复盘结果。分析内容受拍摄角度、视频清晰度、模型能力和服务器状态影响，仅供运动训练参考，不构成医疗诊断、专业裁判结论或安全保证。',
          ),
          (
            title: '二、使用规则',
            body:
                '用户应确保有权上传和处理视频，不得上传违法内容、侵犯他人隐私或著作权的内容，不得恶意占用任务队列、攻击服务或绕过使用限制。每名用户最多保留3个等待任务，每分钟最多创建2个任务。',
          ),
          (
            title: '三、内容与知识产权',
            body:
                '用户保留其合法上传内容的权利，并授权智羽在完成分析所必需的范围内处理该内容。智羽的软件界面、分析逻辑和项目资料受相应知识产权规则保护。',
          ),
          (
            title: '四、服务变化与责任边界',
            body:
                '测试阶段可能出现维护、网络中断或模型误差。团队会尽力保障服务稳定，但对超出合理控制范围的中断不作绝对承诺。用户应自行保留重要原视频和报告副本。',
          ),
          (
            title: '五、协议更新与联系',
            body:
                '功能或法规发生变化时，本协议可能更新。重要变化会通过应用或网站说明。继续使用更新后的服务视为接受新版本；如有异议，可停止使用并申请删除数据。',
          ),
        ],
      ),
    LegalDocumentType.personalInformation => (
        title: '个人信息收集清单',
        sections: [
          (
            title: '匿名用户标识',
            body:
                '场景：区分不同用户的任务与历史记录。方式：首次使用时随机生成。范围：不要求真实姓名、手机号或身份证。保存位置：本机及中心服务器。',
          ),
          (
            title: '训练视频与球场角点',
            body:
                '场景：生成轨迹、热力图、精彩片段和训练报告。方式：用户主动选择或从合作球馆主动获取。保存位置：中心服务器；本机是否保存由用户决定。',
          ),
          (
            title: '任务与报告信息',
            body:
                '场景：显示进度、历史记录和离线报告。内容：文件显示名、任务时间、状态、指标和结果文件。保存位置：中心服务器；用户主动保存后也会写入本机。',
          ),
          (
            title: '头像、昵称、签到和设置',
            body: '场景：个性化展示与使用偏好。方式：用户主动填写或选择。保存位置：仅保存在当前设备，不上传中心服务器。',
          ),
          (
            title: '位置与二维码内容',
            body: '位置仅在主动查找附近球馆时读取一次，不上传中心服务器；二维码仅在扫码连接球馆时解析，用于取得球馆服务地址和标识。',
          ),
          (
            title: '网络与运行日志',
            body: '中心服务器及网络服务可能记录请求时间、网络地址、接口状态和错误信息，用于安全、故障排查和稳定性维护，不用于广告画像。',
          ),
        ],
      ),
    LegalDocumentType.thirdPartySharing => (
        title: '第三方信息共享清单',
        sections: [
          (
            title: 'Cloudflare',
            body:
                '用途：提供 HTTPS、域名解析和安全隧道。可能处理：网络地址、请求时间、请求路径及必要的传输数据。触发条件：访问公网 API 或官方网站。',
          ),
          (
            title: '高德地图、百度地图与美团',
            body:
                '用途：查找附近羽毛球馆、查看营业信息和导航。当前应用通过外部链接或已安装地图应用跳转，不集成地图 SDK。只有用户主动点击时才会打开对应服务，其后数据处理遵循该服务的隐私规则。',
          ),
          (
            title: 'Apple 与 Android 系统服务',
            body: '用途：应用分发、系统权限、相册、相机、定位和本地通知。可能处理范围由用户设备系统和商店账户设置决定。',
          ),
          (
            title: '开源组件',
            body:
                '应用使用 Flutter 及视频播放、文件选择、二维码识别、权限、定位和通知等开源组件。这些组件在本机完成对应能力；除上述网络服务外，项目没有接入广告、用户画像或商业统计 SDK。',
          ),
        ],
      ),
    LegalDocumentType.cooperation => (
        title: '商务合作',
        sections: [
          (
            title: '合作球馆',
            body:
                '支持球馆部署固定机位与边缘设备，通过二维码向用户提供可选择时间段的训练视频，并接入智羽分析服务。合作前会明确视频授权、保存期限和设备维护责任。',
          ),
          (
            title: '赛事与校园活动',
            body: '可为校园赛事、社团训练和羽毛球活动提供视频复盘展示、示例报告和技术支持。涉及参赛者视频时，应提前完成肖像和隐私告知。',
          ),
          (
            title: '品牌与内容合作',
            body: '欢迎合规的羽毛球装备、训练内容和运动服务合作。项目不接受虚假测评、隐性广告或无法验证的数据宣传。',
          ),
          (
            title: '联系渠道',
            body: '请通过智羽支持页面说明合作单位、联系人、合作场景和预计规模，项目团队确认后再沟通技术与运营方案。',
          ),
        ],
      ),
  };
}
