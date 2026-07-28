import 'dart:async';

import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/admin_api.dart';

enum AdminTab {
  overview,
  trips,
  users,
  drivers,
  monitoring,
  live,
  support,
  promos,
  pricing,
  comparison
}

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
    this.driversPendingOnly = false,
    this.promos = const [],
    this.fares = const [],
    this.surge = AdminSurge.empty,
    this.comparisonModels = const [],
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

  /// Drivers tab: show only unverified (pending KYC) drivers.
  final bool driversPendingOnly;

  final List<AdminPromo> promos;
  final List<AdminFare> fares;
  final AdminSurge surge;
  final List<AdminComparisonModel> comparisonModels;

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
    bool? driversPendingOnly,
    List<AdminPromo>? promos,
    List<AdminFare>? fares,
    AdminSurge? surge,
    List<AdminComparisonModel>? comparisonModels,
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
      driversPendingOnly: driversPendingOnly ?? this.driversPendingOnly,
      promos: promos ?? this.promos,
      fares: fares ?? this.fares,
      surge: surge ?? this.surge,
      comparisonModels: comparisonModels ?? this.comparisonModels,
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
        driversPendingOnly,
        promos,
        fares,
        surge,
        comparisonModels,
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
          final drivers =
              await _api.drivers(pending: state.driversPendingOnly);
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
        case AdminTab.promos:
          emit(state.copyWith(loading: false, promos: await _api.promos()));
        case AdminTab.pricing:
          final fares = await _api.fares();
          final surge = await _api.surge();
          emit(state.copyWith(loading: false, fares: fares, surge: surge));
        case AdminTab.comparison:
          final models = await _api.comparisonModels();
          emit(state.copyWith(loading: false, comparisonModels: models));
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
        case AdminTab.promos:
        case AdminTab.pricing:
        case AdminTab.comparison:
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

  void setDriversPendingOnly(bool pending) {
    emit(state.copyWith(driversPendingOnly: pending));
    unawaited(refresh());
  }

  /// Approve or reject a driver's documents (KYC gate for going online).
  Future<void> verifyDriver(AdminDriver driver, bool approved) async {
    try {
      await _api.verifyDriver(driver.id, approved);
      await refresh();
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  /// Create a promo code. Rethrows so the dialog can surface success/failure.
  Future<void> createPromo(Map<String, dynamic> body) async {
    try {
      await _api.createPromo(body);
      await refresh();
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      rethrow;
    }
  }

  Future<void> setPromoActive(AdminPromo promo, bool active) async {
    try {
      await _api.setPromoActive(promo.code, active);
      await refresh();
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  Future<void> updateFare(String tier, Map<String, dynamic> body) async {
    try {
      await _api.updateFare(tier, body);
      await refresh();
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      rethrow;
    }
  }

  Future<void> setSurge(double multiplier) async {
    try {
      await _api.setSurge(multiplier);
      await refresh();
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  /// Record an observed real competitor fare; the backend re-fits that
  /// provider's rate card once it has enough samples. Rethrows so the dialog
  /// can surface success/failure.
  Future<void> recordFareSample(Map<String, dynamic> body) async {
    try {
      await _api.recordFareSample(body);
      await refresh();
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      rethrow;
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
