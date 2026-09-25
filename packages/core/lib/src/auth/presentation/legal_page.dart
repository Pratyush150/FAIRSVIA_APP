import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The legal documents linked from the login screen.
enum LegalDocument {
  terms('Terms of Service', String.fromEnvironment('TERMS_URL')),
  privacy('Privacy Policy', String.fromEnvironment('PRIVACY_URL'));

  const LegalDocument(this.title, this.url);

  final String title;

  /// Public URL of the published document, set at build time with
  /// `--dart-define=TERMS_URL=…` / `PRIVACY_URL=…`. Empty until the documents
  /// are published: neither has a public URL yet (see
  /// docs/remaining-work-plan.md, "Privacy policy + terms links"), so none is
  /// hardcoded here.
  final String url;
}

/// Opens [doc]: its public page in the browser when the build has a URL for
/// it, otherwise the in-app [LegalPage] placeholder.
Future<void> openLegalDocument(
  BuildContext context,
  LegalDocument doc, {
  Future<bool> Function(Uri)? launch,
}) async {
  if (doc.url.isNotEmpty) {
    final opened =
        await (launch ??
            (u) => launchUrl(u, mode: LaunchMode.externalApplication))(
          Uri.parse(doc.url),
        );
    if (opened) return;
  }
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => LegalPage(document: doc)));
}

/// In-app stand-in for a legal document that has not been published yet.
/// Says so plainly rather than showing unreviewed legal text as if in force.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = switch (document) {
      LegalDocument.terms =>
        "${AppBrand.name}'s Terms of Service are being finalised and are not "
            'published yet. The full text will appear here before launch.',
      LegalDocument.privacy =>
        "${AppBrand.name}'s Privacy Policy is being finalised and is not "
            'published yet. The full text will appear here before launch.',
    };
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.pill),
                ),
                child: Text(
                  'Draft — not yet published',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.warningTextOf(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(body, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
