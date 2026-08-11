import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One of the Lucide SVGs bundled from `resources/icons/` (see pubspec.yaml
/// and the LICENSE file copied alongside them). `name` is the file's
/// basename without extension, e.g. `LucideIcon('git-branch')`.
class LucideIcon extends StatelessWidget {
  const LucideIcon(this.name, {super.key, this.size = 16, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}
