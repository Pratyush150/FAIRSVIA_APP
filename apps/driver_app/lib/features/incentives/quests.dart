import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// "11 AM", "7:30 PM"; another day gets its date first ("26 Sep, 11 AM").
String questEndsLabel(DateTime endsAt, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final h = endsAt.hour % 12 == 0 ? 12 : endsAt.hour % 12;
  final ampm = endsAt.hour < 12 ? 'AM' : 'PM';
  final time = endsAt.minute == 0
      ? '$h $ampm'
      : '$h:${endsAt.minute.toString().padLeft(2, '0')} $ampm';
  final sameDay =
      endsAt.year == n.year && endsAt.month == n.month && endsAt.day == n.day;
  // A quest that runs to midnight "ends at midnight", not "12 AM tomorrow".
  if (endsAt.hour == 0 && endsAt.minute == 0) {
    final eve = endsAt.subtract(const Duration(minutes: 1));
    if (eve.year == n.year && eve.month == n.month && eve.day == n.day) {
      return 'midnight';
    }
  }
  if (sameDay) return time;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${endsAt.day} ${months[endsAt.month - 1]}, $time';
}

/// "6 of 10 trips · ₹150 bonus · ends 11 AM"
String questLine(DriverQuest q, {DateTime? now}) {
  final bonus = Fmt.money(q.bonus, q.currency);
  if (q.paid) return '${q.target} of ${q.target} trips · $bonus bonus paid';
  if (q.status == 'ended') {
    return '${q.progress} of ${q.target} trips · ended';
  }
  if (q.status == 'upcoming' && q.startsAt != null) {
    return '${q.target} trips · $bonus bonus · '
        'starts ${questEndsLabel(q.startsAt!, now: now)}';
  }
  return '${q.progress} of ${q.target} trips · $bonus bonus · '
      'ends ${questEndsLabel(q.endsAt, now: now)}';
}

/// One quest: title, progress bar and the "6 of 10 trips · …" line.
class QuestTile extends StatelessWidget {
  const QuestTile({super.key, required this.quest, this.now});

  final DriverQuest quest;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final done = quest.completed;
    return Semantics(
      container: true,
      label: '${quest.title}. ${questLine(quest, now: now)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                done
                    ? PhosphorIconsFill.checkCircle
                    : PhosphorIconsRegular.flag,
                size: 18,
                color: done ? AppColors.success : AppColors.iconNeutralFor(dark),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  quest.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: quest.fraction,
              minHeight: 6,
              color: done ? AppColors.success : AppColors.accent,
              backgroundColor:
                  dark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            questLine(quest, now: now),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Quests card on the driver's online / offline sheet: the most urgent
/// running quest, tap for the full list. Hidden when there are none. When a
/// quest completes (a `quest:completed` push, or a reload that finds one
/// finished that was unfinished before) it celebrates with confetti once.
class DriverQuestsCard extends StatefulWidget {
  const DriverQuestsCard({
    super.key,
    required this.load,
    this.completions,
    this.onOpenAll,
  });

  final Future<List<DriverQuest>> Function() load;

  /// `quest:completed` pushes; null in tests that don't need it.
  final Stream<Map<String, dynamic>>? completions;

  /// Opens the full list; null uses [QuestsPage] with the same loader.
  final VoidCallback? onOpenAll;

  /// Quests seen unfinished in this session — a later sighting of one of
  /// them finished is a completion worth celebrating (not every cold start).
  @visibleForTesting
  static final Set<String> seenUnfinished = {};
  static final Set<String> _celebrated = {};

  @override
  State<DriverQuestsCard> createState() => _DriverQuestsCardState();
}

class _DriverQuestsCardState extends State<DriverQuestsCard> {
  List<DriverQuest> _quests = const [];
  String? _celebrating;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _sub = widget.completions?.listen((e) {
      final title = e['title'] as String? ?? 'Quest';
      final id = e['questId'] as String?;
      _celebrate(id, '$title complete · ${Fmt.money((e['bonus'] as num?)?.toDouble() ?? 0, e['currency'] as String?)} bonus added');
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    List<DriverQuest> qs;
    try {
      qs = await widget.load();
    } catch (_) {
      return; // quests are extra — never an error on the sheet
    }
    if (!mounted) return;
    for (final q in qs) {
      if (!q.completed) {
        DriverQuestsCard.seenUnfinished.add(q.id);
      } else if (DriverQuestsCard.seenUnfinished.remove(q.id)) {
        _celebrate(q.id,
            '${q.title} complete · ${Fmt.money(q.bonus, q.currency)} bonus added');
      }
    }
    setState(() => _quests = qs);
  }

  void _celebrate(String? id, String message) {
    if (id != null && !DriverQuestsCard._celebrated.add(id)) return;
    if (!mounted) return;
    setState(() => _celebrating = message);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _celebrating = null);
    });
  }

  /// Running first (soonest ending), then upcoming; finished last.
  DriverQuest? get _headline {
    final running = _quests.where((q) => q.isActive && !q.completed).toList();
    if (running.isNotEmpty) return running.first;
    final upcoming = _quests.where((q) => q.status == 'upcoming').toList();
    if (upcoming.isNotEmpty) return upcoming.first;
    return _quests.isEmpty ? null : _quests.first;
  }

  @override
  Widget build(BuildContext context) {
    final q = _headline;
    if (q == null && _celebrating == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final more = _quests.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AppCard(
            key: const Key('quests-card'),
            onTap: widget.onOpenAll ??
                () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => QuestsPage(load: widget.load),
                    )),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Quests', style: theme.textTheme.labelLarge),
                    const Spacer(),
                    Text(more > 0 ? '+$more more' : 'See all',
                        style: theme.textTheme.bodySmall),
                    const Icon(PhosphorIconsRegular.caretRight, size: 14),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_celebrating != null)
                  Row(
                    children: [
                      const LottieMoment.success(size: 28),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_celebrating!,
                              key: const Key('quest-celebration'),
                              style: theme.textTheme.bodyMedium),
                        ),
                      ),
                    ],
                  )
                else if (q != null)
                  QuestTile(quest: q),
              ],
            ),
          ),
          if (_celebrating != null)
            const IgnorePointer(child: LottieMoment.confetti(size: 200)),
        ],
      ),
    );
  }
}

/// Every quest the driver can see: running, upcoming and just-finished.
class QuestsPage extends StatefulWidget {
  const QuestsPage({super.key, required this.load});

  final Future<List<DriverQuest>> Function() load;

  @override
  State<QuestsPage> createState() => _QuestsPageState();
}

class _QuestsPageState extends State<QuestsPage> {
  late Future<List<DriverQuest>> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Quests')),
      body: RefreshIndicator(
        onRefresh: () async {
          final f = widget.load();
          setState(() => _future = f);
          await f.catchError((_) => <DriverQuest>[]);
        },
        child: FutureBuilder<List<DriverQuest>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text("Couldn't load quests. Pull to retry.")),
              ]);
            }
            final qs = snap.data ?? const [];
            if (qs.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 120),
                Center(
                  child: Text('No quests right now — check back later.',
                      style: theme.textTheme.bodyMedium),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: qs.length + 1,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    'Finish the trips inside the time window and the bonus '
                    'is added to your earnings automatically.',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return AppCard(child: QuestTile(quest: qs[i - 1]));
              },
            );
          },
        ),
      ),
    );
  }
}
