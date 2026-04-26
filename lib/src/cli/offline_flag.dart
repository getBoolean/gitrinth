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

  bool get isOffline => (argResults?['offline'] as bool?) ?? false;
}
