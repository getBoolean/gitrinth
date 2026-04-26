import 'package:args/command_runner.dart';
import 'package:riverpod/riverpod.dart';

import '../app/providers.dart';
import '../service/console.dart';
import 'runner.dart';

abstract class GitrinthCommand extends Command<int> {
  GitrinthRunner get gitrinthRunner => runner as GitrinthRunner;

  ProviderContainer get container => gitrinthRunner.container;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  Console get console => container.read(consoleProvider);
}
