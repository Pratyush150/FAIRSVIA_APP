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
  // Whether the loaded list has anything to mark; drives the app-bar action.
  bool _hasUnread = false;

  void _noteUnread(List<InboxNotification> list) {
    final unread = list.any((n) => !n.read);
    if (unread == _hasUnread) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _hasUnread = unread);
    });
  }

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
          if (_hasUnread)
            IconButton(
              icon: const Icon(PhosphorIconsRegular.checks),
              tooltip: 'Mark all read',
              onPressed: () => _markAll(context),
            ),
        ],
      ),
      body: AsyncContent<List<InboxNotification>>(
        key: ValueKey(_reloadKey),
        load: widget.inbox.list,
        isEmpty: (list) => list.isEmpty,
        emptyIcon: PhosphorIconsRegular.bell,
        emptyTitle: 'No notifications',
        emptyMessage: 'Trip updates and alerts will show up here.',
        builder: (context, list, _) {
          _noteUnread(list);
          return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final n = list[i];
            return ListTile(
              leading: Icon(
                n.read ? PhosphorIconsRegular.bell : PhosphorIconsRegular.bellRinging,
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
        );
        },
      ),
    );
  }
}
