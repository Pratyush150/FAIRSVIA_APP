import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_models/shared_models.dart';

import 'home_data.dart';

/// Horizontal page padding for a Home section (16 dp).
class HomeSection extends StatelessWidget {
  const HomeSection({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: child,
  );
}

/// "Rate your ride" — the contextual card shown when the newest completed
/// ride has no rating from this rider yet.
///
/// `/trips/history` does not carry the driver's name or photo, so the card
/// names the driver only when [driverName] is supplied, and otherwise says
/// "Rate your last ride" with a generic avatar (see the API gap in the
/// report).
class RateLastRideCard extends StatelessWidget {
  const RateLastRideCard({
    super.key,
    required this.trip,
    required this.onTap,
    this.driverName,
  });

  final Trip trip;
  final String? driverName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = driverName;
    final to = trip.dropoff.address;
    return ContextCard(
      leading: AppAvatar(
        name: name,
        icon: name == null ? PhosphorIconsRegular.car : null,
      ),
      title: name == null ? 'Rate your last ride' : 'Rate your ride with $name',
      subtitle: to == null
          ? null
          : 'To ${RecentDestination(point: trip.dropoff.point, address: to).name}',
      trailing: const Icon(PhosphorIconsFill.star, color: AppColors.star),
      onTap: onTap,
    );
  }
}

/// Stars for a past ride, submitted to the same ratings API the end-of-ride
/// sheet uses. Resolves true once the rating is saved.
Future<bool> showRatePastRideSheet(
  BuildContext context, {
  required Trip trip,
  required Future<void> Function(int stars) submit,
  String? driverName,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _RatePastRide(
      title: driverName == null
          ? 'How was your last ride?'
          : 'How was your ride with $driverName?',
      submit: submit,
    ),
  );
  return saved ?? false;
}

class _RatePastRide extends StatefulWidget {
  const _RatePastRide({required this.title, required this.submit});
  final String title;
  final Future<void> Function(int stars) submit;

  @override
  State<_RatePastRide> createState() => _RatePastRideState();
}

class _RatePastRideState extends State<_RatePastRide> {
  int _stars = 0;
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(_stars);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ApiException ? e.message : "Couldn't save your rating.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: StarRating(
                value: _stars,
                onRate: (v) => setState(() => _stars = v),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Submit rating',
              onPressed: _stars == 0 || _busy ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin-managed ride cards (`/content/ride-cards`, the same source as the
/// in-ride RideCardsSection) as Home promo banners. A promo-code card copies
/// its code; a link card opens its URL.
List<PromoBannerData> promosFromRideCards(
  List<RideCard> cards, {
  required ScaffoldMessengerState messenger,
  Future<bool> Function(String url) openUrl = openExternalUrl,
}) {
  const tones = PromoTone.values;
  return [
    for (var i = 0; i < cards.length; i++)
      PromoBannerData(
        id: cards[i].id,
        headline: cards[i].title,
        subline: cards[i].body,
        art: HomeArt.tag,
        tone: tones[i % tones.length],
        onTap: cards[i].hasAction
            ? () => _actOn(cards[i], messenger, openUrl)
            : null,
      ),
  ];
}

Future<void> _actOn(
  RideCard c,
  ScaffoldMessengerState messenger,
  Future<bool> Function(String url) openUrl,
) async {
  final value = c.ctaValue!;
  if (c.ctaType == 'promo_code') {
    await Clipboard.setData(ClipboardData(text: value));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Code $value copied — add it when you book your next ride.',
          ),
        ),
      );
    return;
  }
  if (!await openUrl(value)) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't open that link.")),
    );
  }
}

/// The Offers tab: the same promo cards as the Home, as a page of their own.
class OffersPage extends StatelessWidget {
  const OffersPage({super.key, required this.promos});

  final List<PromoBannerData> promos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers'),
        automaticallyImplyLeading: false,
      ),
      body: promos.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsRegular.tag,
              title: 'No offers right now',
              message: 'New offers will show up here.',
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              children: [PromoBannerList(promos)],
            ),
    );
  }
}
