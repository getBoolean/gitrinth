import 'package:riverpod/riverpod.dart';

class RunnerSettings {
  final bool verbose;
  final bool quiet;

  /// `null` means "auto" — leave colour to NO_COLOR / TTY detection.
  /// `true` forces ANSI on, `false` forces it off.
  final bool? color;

  final String? configPath;

  const RunnerSettings({
    this.verbose = false,
    this.quiet = false,
    this.color,
    this.configPath,
  });
}

class RunnerSettingsNotifier extends Notifier<RunnerSettings> {
  @override
  RunnerSettings build() => const RunnerSettings();

  void set(RunnerSettings value) => state = value;
}

final runnerSettingsProvider =
    NotifierProvider<RunnerSettingsNotifier, RunnerSettings>(
      RunnerSettingsNotifier.new,
    );
