import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

/// Full-screen destination search. Debounced Places autocomplete via the
/// backend proxy; returns the chosen [PlaceDetails] to the caller.
class DestinationSearchPage extends StatefulWidget {
  const DestinationSearchPage({super.key});

  @override
  State<DestinationSearchPage> createState() => _DestinationSearchPageState();
}

class _DestinationSearchPageState extends State<DestinationSearchPage> {
  final _controller = TextEditingController();
  final _repo = sl<TripRepository>();
  Timer? _debounce;
  List<PlacePrediction> _predictions = [];
  bool _loading = false;
  bool _resolving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _predictions = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    try {
      final results = await _repo.autocomplete(q);
      if (!mounted) return;
      setState(() {
        _predictions = results;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _select(PlacePrediction prediction) async {
    setState(() => _resolving = true);
    try {
      final details = await _repo.placeDetails(prediction.placeId);
      if (!mounted) return;
      Navigator.of(context).pop(details);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Where to?'),
        titleTextStyle: theme.textTheme.titleLarge,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Search destination',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      )
                    : (_controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _controller.clear();
                              _onChanged('');
                              setState(() {});
                            },
                          )
                        : null),
              ),
              onChanged: (v) {
                _onChanged(v);
                setState(() {});
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 18, color: AppColors.error),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(_error!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.error)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (_predictions.isEmpty && !_loading && _error == null)
                  EmptyState(
                    icon: Icons.explore_outlined,
                    title: 'Search for a destination',
                    message:
                        'Type an address, landmark, or place to see suggestions.',
                  )
                else
                  ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    itemCount: _predictions.length,
                    separatorBuilder: (_, _) => const Divider(
                        height: 1, indent: 72, endIndent: AppSpacing.lg),
                    itemBuilder: (context, i) {
                      final p = _predictions[i];
                      return InkWell(
                        onTap: _resolving ? null : () => _select(p),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md,
                          ),
                          child: Row(
                            children: [
                              Container(
                                height: 40,
                                width: 40,
                                decoration: const BoxDecoration(
                                  color: AppColors.surfaceMutedLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.location_on_rounded,
                                    size: 20,
                                    color: AppColors.textSecondaryLight),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.primaryText,
                                        style: theme.textTheme.titleSmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    if (p.secondaryText.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(p.secondaryText,
                                          style: theme.textTheme.bodyMedium,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ],
                                ),
                              ),
                              const Icon(Icons.north_east_rounded,
                                  size: 18,
                                  color: AppColors.textTertiaryLight),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                if (_resolving)
                  Container(
                    color: AppColors.scrim,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
