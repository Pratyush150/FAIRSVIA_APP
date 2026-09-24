import 'package:flutter/material.dart';

import '../theme/app_ink.dart';

/// A section title with an optional trailing action (e.g. "See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // THEME=ink: a small-caps label, not a title.
              Text(title, style: inkSectionLabel(context, text.titleLarge)),
              if (subtitle != null)
                Text(subtitle!, style: text.bodyMedium),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
