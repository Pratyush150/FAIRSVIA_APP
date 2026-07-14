import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import 'format.dart';
import 'inbox_remote_data_source.dart';
import 'widgets/async_content.dart';

/// The in-app notification inbox (`GET /me/notifications`). Marks everything
/// read on open via the "Mark all read" action.
class InboxPage extends StatefulWidget {
  const InboxPage({super.key, required this.inbox});

  final InboxRemoteDataSource inbox;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  int _reloadKey = 0;

  Future<void> _markAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.inbox.markAllRead();
      if (mounted) setState(() => _reloadKey++);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all read',
            onPressed: () => _markAll(context),
          ),
        ],
      ),
      body: AsyncContent<List<InboxNotification>>(
        key: ValueKey(_reloadKey),
        load: widget.inbox.list,
        isEmpty: (list) => list.isEmpty,
        emptyIcon: Icons.notifications_none,
        emptyTitle: 'No notifications',
        emptyMessage: 'Trip updates and alerts will show up here.',
        builder: (context, list, _) => ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final n = list[i];
            return ListTile(
              leading: Icon(
                n.read ? Icons.notifications_none : Icons.notifications_active,
                color: n.read ? null : AppColors.accent,
              ),
              title: Text(
                n.title,
                style: TextStyle(
                  fontWeight: n.read ? FontWeight.normal : FontWeight.w600,
                ),
              ),
              subtitle: Text(n.body),
              trailing: n.createdAt != null
                  ? Text(
                      Fmt.dateTime(n.createdAt!),
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }
}
