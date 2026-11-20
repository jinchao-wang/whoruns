/// 展示用的格式化工具。
class Fmt {
  const Fmt._();

  /// 时长（毫秒） -> 「2 小时 13 分」。
  static String duration(int millis) {
    if (millis <= 0) return '0 分钟';
    final minutes = millis ~/ 60000;
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    if (hours < 24) {
      return restMinutes == 0 ? '$hours 小时' : '$hours 小时 $restMinutes 分';
    }
    final days = hours ~/ 24;
    final restHours = hours % 24;
    return restHours == 0 ? '$days 天' : '$days 天 $restHours 小时';
  }

  /// 字节 -> 「320 MB」。
  static String bytes(int value) {
    if (value < 0) return '读不到';
    if (value < 1024) return '$value B';
    final kb = value / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  /// 时间戳 -> 「11-20 14:32」。
  static String stamp(int millis) {
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  /// 相对时间 -> 「3 分钟前」。
  static String ago(DateTime? time) {
    if (time == null) return '还没查过';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  /// 字节数 -> GB，用于存储展示。
  static String gb(int bytes) => '${(bytes / 1073741824).toStringAsFixed(1)} GB';
}
