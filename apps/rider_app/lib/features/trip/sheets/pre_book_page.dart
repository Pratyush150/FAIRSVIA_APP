part of 'ride_sheets.dart';

/// Book a ride for later without leaving the one under way. Starts from where
/// this ride ends, so the common case — the ride back — is one tap from done.
/// Independent of [TripCubit], which is busy with the live ride.
class PreBookPage extends StatefulWidget {
  const PreBookPage({
    super.key,
    required this.repository,
    this.pickup,
    this.pickupAddr,
    this.paymentMode = 'card',
    this.paymentMethodId,
    this.payments,
    this.initialWhen,
    this.initialDropoff,
    this.initialDropoffAddr,
  });

  final TripRepository repository;
  final GeoPoint? pickup;
  final String? pickupAddr;

  /// The payment the page starts on; the rider can switch it here.
  final String paymentMode;

  /// The saved card to start on (card mode), if one was already chosen.
  final String? paymentMethodId;

  /// Source of the rider's saved cards for the Card / Cash choice. Null (in
  /// tests) leaves the choice to Card or Cash alone.
  final PaymentsRemoteDataSource? payments;

  /// Pre-selected time (tests; a future "book again at the same time").
  final DateTime? initialWhen;

  /// Pre-selected destination ("book this trip again").
  final GeoPoint? initialDropoff;
  final String? initialDropoffAddr;

  @override
  State<PreBookPage> createState() => _PreBookPageState();
}

class _PreBookPageState extends State<PreBookPage> {
  GeoPoint? _pickup;
  String? _pickupAddr;
  GeoPoint? _dropoff;
  String? _dropoffAddr;
  DateTime? _when;
  TripEstimate? _estimate;
  String? _tier;
  bool _estimating = false;
  bool _booking = false;
  String? _error;
  String? _notice;
  late String _mode;
  String? _methodId;
  List<Map<String, dynamic>> _cards = const [];

  @override
  void initState() {
    super.initState();
    _mode = widget.paymentMode;
    _methodId = widget.paymentMethodId;
    unawaited(_loadCards());
    _pickup = widget.pickup;
    _pickupAddr = widget.pickupAddr;
    _when = widget.initialWhen;
    _dropoff = widget.initialDropoff;
    _dropoffAddr = widget.initialDropoffAddr;
    if (_pickup != null && _dropoff != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reestimate());
    }
  }

  /// Best-effort: without the list the chips still offer Card and Cash.
  Future<void> _loadCards() async {
    final payments = widget.payments;
    if (payments == null) return;
    try {
      final cards = await payments.methods();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        // "Card" can't be the selection when there is no card on file — the
        // server would refuse the booking — so start on Cash instead.
        if (cards.isEmpty && _mode == 'card') _mode = 'cash';
      });
    } catch (_) {}
  }

  /// The saved card in effect: the chosen one, else the default, else the
  /// first. Null with no saved cards.
  Map<String, dynamic>? get _activeCard {
    if (_cards.isEmpty) return null;
    for (final c in _cards) {
      if (c['id'] == _methodId) return c;
    }
    for (final c in _cards) {
      if (c['isDefault'] == true) return c;
    }
    return _cards.first;
  }

  void _setMode(String mode, {String? methodId}) => setState(() {
    _mode = mode;
    _methodId = mode == 'cash' ? null : (methodId ?? _methodId);
    if (_error != null && _paymentError) _error = null;
  });

  bool _paymentError = false;

  Future<void> _tapCard() async {
    final payments = widget.payments;
    if (payments != null && _cards.isEmpty) {
      // No card on file: add one, then pay with it.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentMethodsPage(
            payments: payments,
            stripeCardAdder: sl.isRegistered<StripeCardAdder>()
                ? sl<StripeCardAdder>()
                : null,
          ),
        ),
      );
      await _loadCards();
      if (mounted && _cards.isNotEmpty) _setMode('card');
      return;
    }
    if (_cards.length > 1) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetCtx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in _cards)
                ListTile(
                  leading: const Icon(PhosphorIconsRegular.creditCard),
                  title: Text(_PaymentModeToggle._cardLabel(c)),
                  trailing: c['id'] == _activeCard?['id']
                      ? Icon(
                          PhosphorIconsRegular.check,
                          color: AppColors.accent,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetCtx).pop(c['id'] as String),
                ),
            ],
          ),
        ),
      );
      if (picked != null) _setMode('card', methodId: picked);
      return;
    }
    _setMode('card');
  }

  Future<PlaceDetails?> _search(GeoPoint? near) {
    return Navigator.of(context).push<PlaceDetails>(
      MaterialPageRoute(
        builder: (_) =>
            DestinationSearchPage(singleDestination: true, initialPickup: near),
      ),
    );
  }

  Future<void> _choosePickup() async {
    final p = await _search(_pickup);
    if (p == null) return;
    setState(() {
      _pickup = p.location;
      _pickupAddr = p.address;
    });
    await _reestimate();
  }

  Future<void> _chooseDropoff() async {
    final p = await _search(_pickup);
    if (p == null) return;
    setState(() {
      _dropoff = p.location;
      _dropoffAddr = p.address;
    });
    await _reestimate();
  }

  Future<void> _chooseTime() async {
    final when = await pickRideTime(context);
    if (when != null) setState(() => _when = when);
  }

  Future<void> _reestimate() async {
    final from = _pickup;
    final to = _dropoff;
    if (from == null || to == null) return;
    setState(() {
      _estimating = true;
      _error = null;
    });
    try {
      final e = await widget.repository.estimate(from, to);
      if (!mounted) return;
      setState(() {
        _estimate = e;
        final stillOffered = e.tiers.any((t) => t.tier == _tier);
        // Availability now says nothing about a later pickup, so pre-pick by
        // seats alone: the cheapest ride with room for more than one (the
        // one-seat bike leads the list), as FareTier.defaultTier does.
        if (!stillOffered) {
          _tier = e.tiers.isEmpty
              ? null
              : e.tiers
                    .firstWhere(
                      (t) => t.capacity > 1,
                      orElse: () => e.tiers.first,
                    )
                    .tier;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  FareTier? get _selected {
    for (final t in _estimate?.tiers ?? const <FareTier>[]) {
      if (t.tier == _tier) return t;
    }
    return null;
  }

  bool get _ready =>
      _pickup != null && _dropoff != null && _when != null && _selected != null;

  Future<void> _book() async {
    final tier = _selected;
    if (!_ready || tier == null) return;
    setState(() {
      _booking = true;
      _error = null;
      _notice = null;
      _paymentError = false;
    });
    try {
      final trip = await widget.repository.createTrip(
        pickup: _pickup!,
        dropoff: _dropoff!,
        tier: tier.tier,
        pickupAddr: _pickupAddr,
        dropoffAddr: _dropoffAddr,
        paymentMode: _mode,
        paymentMethodId: _mode == 'card'
            ? (_activeCard?['id'] as String?)
            : null,
        scheduledAt: _when,
        quotedFare: tier.fare,
        quotedSurge: _estimate?.surge,
      );
      if (mounted) Navigator.of(context).pop(trip);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == TripCubit.priceChangedCode) {
        setState(
          () => _notice =
              'Prices changed while you were booking. '
              'Check the new fare, then schedule.',
        );
        await _reestimate();
      } else {
        setState(() {
          _error = e.message;
          _paymentError = e.code == 'PAYMENT_METHOD_REQUIRED';
        });
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tier = _selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Pre-book a ride')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: [
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _PreBookRow(
                          icon: PhosphorIconsRegular.record,
                          iconColor: AppColors.accent,
                          label: 'Pickup',
                          value: _pickupAddr ?? 'Choose a pickup',
                          onTap: _choosePickup,
                        ),
                        const Divider(height: 1, indent: 52),
                        _PreBookRow(
                          // mapPin, as on Ride details and the receipt: a
                          // 24 px filled square read as a heavy block here.
                          icon: PhosphorIconsRegular.mapPin,
                          iconColor: AppColors.accent,
                          label: 'Destination',
                          value: _dropoffAddr ?? 'Where to?',
                          placeholder: _dropoff == null,
                          onTap: _chooseDropoff,
                        ),
                        const Divider(height: 1, indent: 52),
                        _PreBookRow(
                          icon: PhosphorIconsRegular.calendarBlank,
                          iconColor: AppColors.accentInk,
                          label: 'When',
                          value: _when == null
                              ? 'Choose a date and time'
                              : _formatSchedule(_when!),
                          placeholder: _when == null,
                          onTap: _chooseTime,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_estimating)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_estimate != null) ...[
                    Text('Choose a ride', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    for (final t in _estimate!.tiers) ...[
                      _PreBookTier(
                        tier: t,
                        selected: t.tier == _tier,
                        onTap: () => setState(() => _tier = t.tier),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    Text(
                      'This is the fare we quote now. As with any ride, the '
                      'final fare follows the route actually driven.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _notice!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.warningTextOf(context),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // How it's paid sits right above the button that commits
                  // to it, as on the ride-options sheet.
                  Row(
                    children: [
                      Expanded(
                        key: const Key('prebook-pay-card'),
                        child: _PayChip(
                          icon: PhosphorIconsRegular.creditCard,
                          label: _activeCard != null
                              ? _PaymentModeToggle._cardLabel(_activeCard!)
                              : (widget.payments != null ? 'Add card' : 'Card'),
                          selected: _mode == 'card',
                          trailing: _cards.length > 1
                              ? PhosphorIconsRegular.caretDown
                              : null,
                          onTap: _tapCard,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        key: const Key('prebook-pay-cash'),
                        child: _PayChip(
                          icon: PhosphorIconsRegular.money,
                          label: 'Cash',
                          selected: _mode == 'cash',
                          onTap: () => _setMode('cash'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(
                    label: tier == null
                        ? 'Schedule ride'
                        : 'Schedule ${tier.label} · ${Fmt.money(tier.fare, tier.currency)}',
                    loading: _booking,
                    onPressed: _ready && !_booking ? _book : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreBookRow extends StatelessWidget {
  const _PreBookRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: placeholder
                          ? (dark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(PhosphorIconsRegular.caretRight),
          ],
        ),
      ),
    );
  }
}

class _PreBookTier extends StatelessWidget {
  const _PreBookTier({
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final FareTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected ? AppColors.accent : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
          color: selected ? AppColors.accent.withValues(alpha: 0.08) : null,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tier.label, style: theme.textTheme.titleMedium),
                      Text(
                        tier.capacity == 1
                            ? '1 seat'
                            : '${tier.capacity} seats',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  Fmt.money(tier.fare, tier.currency),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
