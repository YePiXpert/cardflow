import 'package:flutter/material.dart';

import '../../app/widgets/state_views.dart';

/// 公测版的固定文字：P-22 首次使用页底部与「关于」共用同一段公测说明。版本号只在 [PublicBeta.version] 一处，
/// 必须与 `pubspec.yaml` 的版本名相同（`test/app/public_beta_test.dart` 读取 pubspec 断言二者相等，改版本时一起改）。
abstract final class PublicBeta {
  /// App 名称（与诊断报告的标题一致）。
  static const String appName = '卡序 CardFlow';

  /// 公测版本号：与 `pubspec.yaml` 的版本名一致（测试核对；构建号由 CI 的运行序号给出）。
  static const String version = '0.0.1';

  /// "公测版"标识。
  static const String badge = '公测版';

  /// 公测说明的标题。
  static const String noteTitle = '公测说明';

  /// 公测说明：数据只在本机、删除即永久丢失、还没有备份与导出。
  static const String note =
      '公测版 $version：数据只保存在这台 iPhone 的加密数据库里，不上传任何服务器。'
      '删除 App 或「重置本地数据」会永久删除全部数据；目前还没有备份与导出，后续版本提供。';

  /// 源码地址（纯文本，可选中复制；App 内不打开浏览器）。
  static const String sourceAddress = 'github.com/YePiXpert/cardflow';

  /// 反馈方式。
  static const String feedback = '我的 › 诊断信息 › 复制诊断信息，附上问题描述发到 GitHub Issues';
}

/// 公测说明（提示块，提醒色 + 图标 + 文字）：P-22 底部与「关于」共用。
class PublicBetaNotice extends StatelessWidget {
  const PublicBetaNotice({super.key, this.margin = NoticeCard.defaultMargin});

  /// 外边距（P-22 的列表本身有内边距，传 [EdgeInsets.zero]）。
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => NoticeCard(
    icon: Icons.info_outline,
    text: PublicBeta.note,
    margin: margin,
  );
}
