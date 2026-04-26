import '../app/providers.dart';
import 'base_command.dart';

mixin OfflineFlag on GitrinthCommand {
  void addOfflineFlag({String? helpOverride}) {
    argParser.addFlag(
      'offline',
      negatable: false,
      help:
          helpOverride ??
          'Use cached versions only; do not hit the network. '
              'Resolution narrows to versions already in the cache.',
    );
  }

  /// Reads the parsed `--offline` value, syncs it into [offlineProvider]
  /// (so the Dio interceptor short-circuits any unguarded network call),
  /// and returns it. Call once at the top of `run()`.
  bool readOfflineFlag() {
    final offline = (argResults?['offline'] as bool?) ?? false;
    container.read(offlineProvider.notifier).set(offline);
    return offline;
  }

  /// The current offline state. Reads the live [offlineProvider] value
  /// (kept in sync by [readOfflineFlag]) so the answer matches whatever
  /// the Dio interceptor is gating on, even if a caller mutates the
  /// provider directly.
  bool get isOffline => container.read(offlineProvider);
}
