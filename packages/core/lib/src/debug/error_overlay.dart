import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

/// Holds the most recent uncaught error so it can be painted on screen. This
/// exists so failures are visible during self-hosted web testing (SSH server,
/// no DevTools handy) — the error shows up in a red banner instead of only in
/// the browser console.
final ValueNotifier<String?> lastCaughtError = ValueNotifier<String?>(null);

/// Records [error] (and the top of its [stack]) into [lastCaughtError].
void reportError(Object error, [StackTrace? stack]) {
  // Transient realtime-socket close errors are expected: the OS closes the
  // WebSocket when the app is backgrounded and network blips drop it. The
  // client auto-reconnects and the ConnectionBanner already tells the user, so
  // these must not surface as a scary red error banner.
  final text = error.toString();
  if (text.contains('WebSocketConnectionClosed') ||
      text.contains('WebSocketChannelException')) {
    debugPrint('IGNORED transient socket-close error: $error');
    return;
  }
  final trace = stack?.toString() ?? '';
  final head = trace.isEmpty
      ? ''
      : '\n\n${trace.split('\n').take(8).join('\n')}';
  // Also log so it still appears in the console for anyone who has it open.
  debugPrint('UNCAUGHT: $error$head');
  final message = '$error$head';
  // Errors are often reported mid-build (FlutterError.onError fires while the
  // framework is building/laying out). Setting the ValueNotifier then would
  // mark the overlay dirty during build and throw a secondary
  // "setState() called during build" — so defer to after the frame.
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks) {
    lastCaughtError.value = message;
  } else {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      lastCaughtError.value = message;
    });
  }
}

/// Surfaces every bloc error (e.g. an exception thrown inside an event handler,
/// which flutter_bloc otherwise swallows in release) to the on-screen banner.
class DebugBlocObserver extends BlocObserver {
  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    reportError(error, stackTrace);
    super.onError(bloc, error, stackTrace);
  }
}

/// Installs global Flutter + bloc error hooks that route into [reportError].
/// Call once, inside the same zone as `runApp`.
void installErrorHooks() {
  FlutterError.onError = (details) {
    reportError(details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportError(error, stack);
    return true;
  };
  Bloc.observer = DebugBlocObserver();
}

/// Runs [body] (typically async DI setup then `runApp`) inside a guarded zone
/// so even errors thrown outside the Flutter pipeline reach the banner.
void runGuarded(FutureOr<void> Function() body) {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    installErrorHooks();
    await body();
  }, reportError);
}

/// Wraps an app's content with a dismissible red error banner pinned to the
/// bottom. Use as the `builder:` of `MaterialApp`/`MaterialApp.router`.
class ErrorOverlay extends StatelessWidget {
  const ErrorOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<String?>(
          valueListenable: lastCaughtError,
          builder: (context, err, _) {
            if (err == null) return const SizedBox.shrink();
            return Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: const Color(0xFFB00020),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2, right: 8),
                          child: Icon(Icons.error_outline,
                              color: Colors.white, size: 18),
                        ),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: SingleChildScrollView(
                              // Plain Text, not SelectableText: this banner
                              // lives above the app's Navigator, so an
                              // EditableText here has no Overlay and its
                              // "No Overlay widget found" failure replaced
                              // the real error we were trying to show.
                              child: Text(
                                err,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy error',
                          icon: const Icon(Icons.copy, color: Colors.white),
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: err)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => lastCaughtError.value = null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
