import 'dart:async';

import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/admin_api.dart';

enum AdminTab { overview, trips, users, drivers }

class AdminState extends Equatable {
  const AdminState({
    this.tab = AdminTab.overview,
    this.loading = false,
    this.error,
    this.stats,
    this.trips = const [],
    this.users = const [],
    this.drivers = const [],
    this.userQuery = '',
  });

  final AdminTab tab;
  final bool loading;
  final String? error;
  final AdminStats? stats;
  final List<AdminTrip> trips;
  final List<AdminUser> users;
  final List<AdminDriver> drivers;
  final String userQuery;

  AdminState copyWith({
    AdminTab? tab,
    bool? loading,
    String? error,
    bool clearError = false,
    AdminStats? stats,
    List<AdminTrip>? trips,
    List<AdminUser>? users,
    List<AdminDriver>? drivers,
    String? userQuery,
  }) {
    return AdminState(
      tab: tab ?? this.tab,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      stats: stats ?? this.stats,
      trips: trips ?? this.trips,
      users: users ?? this.users,
      drivers: drivers ?? this.drivers,
      userQuery: userQuery ?? this.userQuery,
    );
  }

  @override
  List<Object?> get props =>
      [tab, loading, error, stats, trips, users, drivers, userQuery];
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
    if (state.tab != AdminTab.overview && state.tab != AdminTab.trips) return;
    try {
      if (state.tab == AdminTab.overview) {
        final stats = await _api.stats();
        final trips = await _api.trips(status: 'active', limit: 20);
        emit(state.copyWith(stats: stats, trips: trips));
      } else {
        emit(state.copyWith(trips: await _api.trips(limit: 100)));
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

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
