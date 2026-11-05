import 'package:flutter/material.dart';

import '../theme.dart';
import '../../l10n/l10n.dart';

/// The Arabic wordmark رفيق, in-product: monochrome in `ink-secondary`, dot
/// included, so that the only cinnabar on a following screen is the position.
///
/// Drawn from the handoff's small optical cut (for 24–40px; its dot is larger
/// and raised so it stays legible), tinted to one ink. Never set in another
/// font, recoloured to cinnabar inside the product, or animated.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 26});

  /// 24px minimum.
  final double height;

  static const asset = 'assets/brand/wordmark-ar-small.png';

  @override
  Widget build(BuildContext context) => Semantics(
        label: context.l10n.appName,
        image: true,
        child: Image.asset(
          asset,
          height: height,
          color: context.colors.inkSecondary,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      );
}
