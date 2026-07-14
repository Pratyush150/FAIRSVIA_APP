import 'dart:async';

import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/admin_api.dart';

enum AdminTab { overview, trips, users, drivers, monitoring, live, support }

class AdminState extends Equatable {
  const AdminState({
    this.tab = AdminTab.overview,
    this.loading = false,
    this.error,
    this.stats,
    this.ops,
    this.trips = const [],
    this.users = const [],
    this.drivers = const [],
    this.live = LiveSnapshot.empty,
    this.userQuery = '',
    this.tickets = const [],
    this.ticketFilter = 'open',
  });

  final AdminTab tab;
  final bool loading;
  final String? error;
  final AdminStats? stats;
  final OpsMetrics? ops;
  final List<AdminTrip> trips;
  final List<AdminUser> users;
  final List<AdminDriver> drivers;
  final LiveSnapshot live;
  final String userQuery;
  final List<AdminSupportTicket> tickets;

  /// '' means "all statuses".
  final String ticketFilter;

  AdminState copyWith({
    AdminTab? tab,
    bool? loading,
    String? error,
    bool clearError = false,
    AdminStats? stats,
    OpsMetrics? ops,
    List<AdminTrip>? trips,
    List<AdminUser>? users,
    List<AdminDriver>? drivers,
    LiveSnapshot? live,
    String? userQuery,
    List<AdminSupportTicket>? tickets,
    String? ticketFilter,
  }) {
    return AdminState(
      tab: tab ?? this.tab,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      stats: stats ?? this.stats,
      ops: ops ?? this.ops,
      trips: trips ?? this.trips,
      users: users ?? this.users,
      drivers: drivers ?? this.drivers,
      live: live ?? this.live,
      userQuery: userQuery ?? this.userQuery,
      tickets: tickets ?? this.tickets,
      ticketFilter: ticketFilter ?? this.ticketFilter,
    );
  }

  @override
  List<Object?> get props => [
        tab,
        loading,
        error,
        stats,
        ops,
        trips,
        users,
        drivers,
        live,
        userQuery,
        tickets,
        ticketFilter,
      ];
}

/// Drives the admin dashboard: loads each dataset on demand and auto-refreshes
/// the live views (overview + trips) on a timer.
class AdminCubit extends Cubit<AdminState> {
  AdminCubit(this._api) : super(const AdminState());

  final AdminApi _api;
  Timer? _timer;

  Future<void> start() async {
    await refresh();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _refreshLive(),
    );
  }

  void selectTab(AdminTab tab) {
    emit(state.copyWith(tab: tab, clearError: true));
    unawaited(refresh());
  }

  Future<void> refresh() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      switch (state.tab) {
        case AdminTab.overview:
          final stats = await _api.stats();
          final trips = await _api.trips(status: 'active', limit: 20);
          emit(state.copyWith(loading: false, stats: stats, trips: trips));
        case AdminTab.trips:
          final trips = await _api.trips(limit: 100);
          emit(state.copyWith(loading: false, trips: trips));
        case AdminTab.users:
          final users = await _api.users(q: state.userQuery);
          emit(state.copyWith(loading: false, users: users));
        case AdminTab.drivers:
          final drivers = await _api.drivers();
          emit(state.copyWith(loading: false, drivers: drivers));
        case AdminTab.monitoring:
          final ops = await _api.metrics();
          emit(state.copyWith(loading: false, ops: ops));
        case AdminTab.live:
          final live = await _api.live();
          emit(state.copyWith(loading: false, live: live));
        case AdminTab.support:
          final tickets = await _api.supportTickets(
            status: state.ticketFilter.isEmpty ? null : state.ticketFilter,
          );
          emit(state.copyWith(loading: false, tickets: tickets));
      }
    } on ApiException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  /// Silent refresh for the timer — never flips the loading flag or clobbers
  /// the view with an error banner.
  Future<void> _refreshLive() async {
    try {
      switch (state.tab) {
        case AdminTab.overview:
          final stats = await _api.stats();
          final trips = await _api.trips(status: 'active', limit: 20);
          emit(state.copyWith(stats: stats, trips: trips));
        case AdminTab.trips:
          emit(state.copyWith(trips: await _api.trips(limit: 100)));
        case AdminTab.monitoring:
          emit(state.copyWith(ops: await _api.metrics()));
        case AdminTab.live:
          emit(state.copyWith(live: await _api.live()));
        case AdminTab.users:
        case AdminTab.drivers:
        case AdminTab.support:
          return; // not live-refreshed
      }
    } catch (_) {
      // Ignore transient refresh failures; the next tick retries.
    }
  }

  void setUserQuery(String q) => emit(state.copyWith(userQuery: q));

  Future<void> searchUsers() => refresh();

  Future<void> toggleActive(AdminUser user) async {
    try {
      await _api.setActive(user.id, !user.isActive);
      await refresh();
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  /// Refund a trip (full when [amount] is null). Rethrows so the caller can
  /// surface success/failure inline.
  Future<void> refundTrip(String tripId, {double? amount, String? reason}) async {
    try {
      await _api.refund(tripId, amount: amount, reason: reason);
      await refresh();
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      rethrow;
    }
  }

  void setTicketFilter(String filter) {
    emit(state.copyWith(ticketFilter: filter));
    unawaited(refresh());
  }

  Future<AdminSupportTicket> ticketThread(String id) => _api.supportThread(id);

  Future<AdminSupportTicket> replyTicket(String id, String body) =>
      _api.supportReply(id, body);

  /// Change a ticket's status and refresh the queue.
  Future<void> setTicketStatus(String id, String status) async {
    try {
      await _api.supportSetStatus(id, status);
      await refresh();
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
