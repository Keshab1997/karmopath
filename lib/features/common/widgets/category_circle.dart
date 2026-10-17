import 'package:flutter/material.dart';

import '../../../contracts/job.dart';
import '../../../design_system/karmopath_theme.dart';

/// Pastel category visuals.
///
/// Deliberately generic Material icons: docs/DESIGN.md forbids official
/// crests, seals and government emblems. Sliced decorative assets are a
/// captain deliverable, so nothing here is a fake substitute asset.
abstract final class CategoryVisual {
  static IconData iconFor(JobCategory category) => switch (category) {
    JobCategory.police => Icons.local_police_outlined,
    JobCategory.railway => Icons.train_outlined,
    JobCategory.banking => Icons.account_balance_outlined,
    JobCategory.teaching => Icons.school_outlined,
    JobCategory.medical => Icons.medical_services_outlined,
    JobCategory.office => Icons.work_outline,
    JobCategory.other => Icons.category_outlined,
  };

  static Color backgroundFor(JobCategory category) => switch (category) {
    JobCategory.police => const Color(0xFFE8E5FB),
    JobCategory.railway => const Color(0xFFDDF0EE),
    JobCategory.banking => const Color(0xFFFDEFD9),
    JobCategory.teaching => const Color(0xFFFAE3E0),
    JobCategory.medical => const Color(0xFFE2F3E4),
    JobCategory.office => const Color(0xFFEDE7F8),
    JobCategory.other => const Color(0xFFE9E7E3),
  };

  static Color foregroundFor(JobCategory category) => switch (category) {
    JobCategory.police => const Color(0xFF4F46A5),
    JobCategory.railway => KarmopathTheme.teal,
    JobCategory.banking => const Color(0xFFB7791F),
    JobCategory.teaching => const Color(0xFFC0452E),
    JobCategory.medical => const Color(0xFF2F855A),
    JobCategory.office => const Color(0xFF6B46C1),
    JobCategory.other => const Color(0xFF4B5563),
  };
}

/// Round pastel badge with a generic category icon (decorative).
class CategoryCircle extends StatelessWidget {
  const CategoryCircle({super.key, required this.category, this.size = 48});

  final JobCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: CategoryVisual.backgroundFor(category),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          CategoryVisual.iconFor(category),
          size: size * 0.5,
          color: CategoryVisual.foregroundFor(category),
        ),
      ),
    );
  }
}
