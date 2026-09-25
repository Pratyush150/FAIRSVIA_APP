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
/// `/trips/history` carries the driver's name and photo, so the card reads
/// "Rate your ride with Aziz" with their avatar. [driverName] overrides the
/// trip's; with neither (an older backend) it says "Rate your last ride" with
/// a generic car avatar.
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
    final full = driverName ?? trip.driverName;
    final first = firstName(full);
    final to = trip.dropoff.address;
    return ContextCard(
      leading: AppAvatar(
        name: full,
        imageUrl: trip.driverAvatarUrl,
        icon: full == null ? PhosphorIconsRegular.car : null,
      ),
      title: first == null
          ? 'Rate your last ride'
          : 'Rate your ride with $first',
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
  final name = firstName(driverName ?? trip.driverName);
  final saved = await showAppModalSheet<bool>(
    context: context,
    builder: (ctx) => _RatePastRide(
      title: name == null
          ? 'How was your last ride?'
          : 'How was your ride with $name?',
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

/// Real offers (`GET /promos/available`) as Home promo banners: the photo
/// look, the offer's title as the headline. Tapping one picks it for the next
/// ride ([onPick]); the caller then opens the destination search.
List<PromoBannerData> promosFromOffers(
  List<AvailablePromo> offers, {
  required void Function(AvailablePromo offer) onPick,
}) {
  const tones = PromoTone.values;
  return [
    for (var i = 0; i < offers.length; i++)
      PromoBannerData(
        id: 'offer-${offers[i].code}',
        headline: offers[i].title,
        subline: '${offers[i].headline} · code ${offers[i].code}',
        image: PromoPhoto.all[i % PromoPhoto.all.length],
        art: HomeArt.tag,
        tone: tones[i % tones.length],
        onTap: () => onPick(offers[i]),
      ),
  ];
}

/// "Ends 3 Oct" / "Ends today" for an offer's expiry.
String offerExpiryLabel(DateTime when, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = when.toLocal();
  if (d.year == n.year && d.month == n.month && d.day == n.day) {
    return 'Ends today';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final year = d.year == n.year ? '' : ' ${d.year}';
  return 'Ends ${d.day} ${months[d.month - 1]}$year';
}

/// The Offers tab: the promos this rider can use right now, from the server.
/// Each card says what it gives and on what terms, with "Apply to next ride"
/// (the next ride sheet then carries the code, priced) and "Copy code".
class OffersPage extends StatefulWidget {
  const OffersPage({
    super.key,
    required this.load,
    required this.onApply,
    required this.onRemove,
    this.selectedCode,
  });

  /// Fetches the offers (throws on a network/API error).
  final Future<List<AvailablePromo>> Function() load;
  final void Function(AvailablePromo offer) onApply;
  final VoidCallback onRemove;

  /// The code already picked for the next ride, if any.
  final String? selectedCode;

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  late Future<List<AvailablePromo>> _future = widget.load();

  Future<void> _refresh() async {
    final f = widget.load();
    setState(() {
      _future = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers'),
        automaticallyImplyLeading: false,
      ),
      body: FutureBuilder<List<AvailablePromo>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EmptyState(
              icon: PhosphorIconsRegular.cloudSlash,
              title: "Couldn't load offers",
              message: 'Check your connection and try again.',
              action: SecondaryButton(label: 'Try again', onPressed: _refresh),
            );
          }
          final offers = snap.data ?? const <AvailablePromo>[];
          if (offers.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: AppSpacing.xxl),
                  EmptyState(
                    icon: PhosphorIconsRegular.tag,
                    title: 'No offers right now',
                    message: 'New offers will show up here.',
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: offers.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) => OfferCard(
                offer: offers[i],
                applied: offers[i].code == widget.selectedCode,
                onApply: () => widget.onApply(offers[i]),
                onRemove: widget.onRemove,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One offer on the Offers page.
class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.applied,
    required this.onApply,
    required this.onRemove,
  });

  final AvailablePromo offer;
  final bool applied;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: offer.code));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Code ${offer.code} copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.textTheme.bodySmall?.color;
    final expiry = offer.expiresAt;
    return AppCard(
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      offer.headline,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentTextFor(dark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _CodeChip(code: offer.code, onCopy: () => _copy(context)),
            ],
          ),
          if (offer.description != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(offer.description!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              offer.conditions,
              if (expiry != null) offerExpiryLabel(expiry),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: AppSpacing.md),
          if (applied)
            Container(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                color: AppColors.success.withValues(alpha: 0.12),
              ),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsFill.checkCircle,
                    size: 20,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Applied — will be used on your next ride',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(onPressed: onRemove, child: const Text('Remove')),
                ],
              ),
            )
          else
            PrimaryButton(label: 'Apply to next ride', onPressed: onApply),
        ],
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, required this.onCopy});
  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: 'Copy code $code',
      excludeSemantics: true,
      child: Material(
        color: AppColors.softFor(dark),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: onCopy,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  code,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(PhosphorIconsRegular.copy, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
