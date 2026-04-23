import 'package:args/command_runner.dart';

import '../io/console.dart';
import 'runner.dart';

abstract class GitrinthCommand extends Command<int> {
  Console get console {
    final r = runner;
    final verbose = r is GitrinthRunner && r.verbose;
    return Console(verbose: verbose);
  }
}
