import 'package:riverpod/riverpod.dart';

import '../service/console.dart';

class RunnerSettings {
  final LogLevel level;

  /// `null` means "auto" — leave colour to NO_COLOR / TTY detection.
  /// `true` forces ANSI on, `false` forces it off.
  final bool? color;

  final String? configPath;

  const RunnerSettings({
    this.level = LogLevel.normal,
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
