import 'dart:io';

import 'package:gitrinth/gitrinth.dart' as gitrinth;

Future<void> main(List<String> arguments) async {
  exitCode = await gitrinth.run(arguments);
}
