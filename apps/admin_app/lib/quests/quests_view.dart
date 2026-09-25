import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'quests_api.dart';

const _tiers = ['economy', 'comfort', 'xl', 'premium', 'auto', 'bike'];

String _when(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Admin console: incentive quests ("complete N trips in a window → bonus").
/// Self-contained (loads through [QuestsApi]) so it adds no cubit state.
class QuestsView extends StatefulWidget {
  const QuestsView({super.key, required this.api});
  final QuestsApi api;

  @override
  State<QuestsView> createState() => _QuestsViewState();
}

class _QuestsViewState extends State<QuestsView> {
  List<AdminQuest>? _quests;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final qs = await widget.api.list();
      if (mounted) setState(() => (_quests = qs, _error = null));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _setActive(AdminQuest q, bool v) async {
    try {
      await widget.api.update(q.id, {'active': v});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qs = _quests;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Driver quests', style: theme.textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                key: const Key('new-quest'),
                onPressed: () async {
                  if (await showNewQuestDialog(context, widget.api)) _load();
                },
                icon: const Icon(PhosphorIconsRegular.plus),
                label: const Text('New quest'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Drivers who complete the target number of trips inside the '
            'window get the bonus credited once, automatically.',
            style: theme.textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: qs == null
                ? const Center(child: CircularProgressIndicator())
                : qs.isEmpty
                    ? const Center(child: Text('No quests yet.'))
                    : ListView.separated(
                        itemCount: qs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final q = qs[i];
                          return ListTile(
                            title: Text(q.title),
                            subtitle: Text(
                              '${q.targetTrips} trips · '
                              '${Fmt.money(q.bonusAmount, q.currency)} bonus · '
                              '${_when(q.startsAt)} → ${_when(q.endsAt)} · '
                              '${q.tiers.isEmpty ? 'all tiers' : q.tiers.join(', ')} · '
                              '${q.awards} paid',
                            ),
                            trailing: Switch(
                              value: q.active,
                              onChanged: (v) => _setActive(q, v),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// The create form. Returns true when a quest was created.
Future<bool> showNewQuestDialog(BuildContext context, QuestsApi api) async {
  final title = TextEditingController();
  final target = TextEditingController(text: '10');
  final bonus = TextEditingController(text: '150');
  final now = DateTime.now();
  var start = DateTime(now.year, now.month, now.day, 7);
  var end = DateTime(now.year, now.month, now.day, 11);
  final tiers = <String>{};
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Future<void> pick(bool isStart) async {
          final base = isStart ? start : end;
          final d = await showDatePicker(
            context: ctx,
            initialDate: base,
            firstDate: now.subtract(const Duration(days: 1)),
            lastDate: now.add(const Duration(days: 90)),
          );
          if (d == null || !ctx.mounted) return;
          final t = await showTimePicker(
              context: ctx, initialTime: TimeOfDay.fromDateTime(base));
          if (t == null) return;
          final v = DateTime(d.year, d.month, d.day, t.hour, t.minute);
          setS(() => isStart ? start = v : end = v);
        }

        return AlertDialog(
          title: const Text('New quest'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('quest-title'),
                    controller: title,
                    decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'Complete 10 trips between 7–11 AM'),
                  ),
                  TextField(
                    key: const Key('quest-target'),
                    controller: target,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Target trips'),
                  ),
                  TextField(
                    key: const Key('quest-bonus'),
                    controller: bonus,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Bonus amount'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pick(true),
                        child: Text('Starts ${_when(start)}'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pick(false),
                        child: Text('Ends ${_when(end)}'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  Text('Tiers (none selected = all tiers)',
                      style: Theme.of(ctx).textTheme.bodySmall),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (final t in _tiers)
                        FilterChip(
                          label: Text(t),
                          selected: tiers.contains(t),
                          onSelected: (v) =>
                              setS(() => v ? tiers.add(t) : tiers.remove(t)),
                        ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(error!,
                          style: TextStyle(color: AppColors.error)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              key: const Key('quest-create'),
              onPressed: () async {
                final n = int.tryParse(target.text.trim());
                final b = double.tryParse(bonus.text.trim());
                if (title.text.trim().length < 3 || n == null || n < 1 ||
                    b == null || b <= 0) {
                  setS(() => error = 'Enter a title, a target ≥ 1 and a bonus.');
                  return;
                }
                if (!end.isAfter(start)) {
                  setS(() => error = 'The end must be after the start.');
                  return;
                }
                try {
                  await api.create({
                    'title': title.text.trim(),
                    'targetTrips': n,
                    'bonusAmount': b,
                    'startsAt': start.toUtc().toIso8601String(),
                    'endsAt': end.toUtc().toIso8601String(),
                    if (tiers.isNotEmpty) 'tiers': tiers.toList(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  setS(() => error = e.message);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    ),
  );
  return ok ?? false;
}
