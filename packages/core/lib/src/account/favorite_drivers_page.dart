import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import 'favorites_remote_data_source.dart';
import 'widgets/async_content.dart';

/// The rider's favourite drivers (`GET /me/favorites`). Dispatch offers these
/// drivers first when they're nearby. Each can be removed here.
class FavoriteDriversPage extends StatefulWidget {
  const FavoriteDriversPage({super.key, required this.favorites});

  final FavoritesRemoteDataSource favorites;

  @override
  State<FavoriteDriversPage> createState() => _FavoriteDriversPageState();
}

class _FavoriteDriversPageState extends State<FavoriteDriversPage> {
  int _reloadKey = 0;

  Future<void> _remove(BuildContext context, FavoriteDriver d) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.favorites.remove(d.driverId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Removed from favourites')),
      );
      if (mounted) setState(() => _reloadKey++);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourite drivers')),
      body: AsyncContent<List<FavoriteDriver>>(
        key: ValueKey(_reloadKey),
        load: widget.favorites.list,
        isEmpty: (list) => list.isEmpty,
        emptyIcon: PhosphorIconsRegular.heart,
        emptyTitle: 'No favourite drivers',
        emptyMessage:
            'Add a driver to favourites after a ride — we’ll try to match you '
            'with them first.',
        builder: (context, list, _) => ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = list[i];
            final subtitle = [
              if (d.vehicleModel != null) d.vehicleModel,
              if (d.plateNumber != null) d.plateNumber,
              if (d.ratingAvg != null) '★ ${d.ratingAvg!.toStringAsFixed(1)}',
            ].whereType<String>().join(' · ');
            return ListTile(
              leading: const CircleAvatar(child: Icon(PhosphorIconsRegular.user)),
              title: Text(d.name ?? 'Driver'),
              subtitle: subtitle.isEmpty ? null : Text(subtitle),
              trailing: IconButton(
                icon: const Icon(PhosphorIconsFill.heart, color: AppColors.error),
                tooltip: 'Remove',
                onPressed: () => _remove(context, d),
              ),
            );
          },
        ),
      ),
    );
  }
}
