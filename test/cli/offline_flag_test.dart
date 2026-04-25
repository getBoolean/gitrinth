import 'package:test/test.dart';

import '../helpers/capture.dart';

void main() {
  group('--offline acceptance per command', () {
    const shouldAccept = [
      'get',
      'upgrade',
      'add',
      'remove',
      'build',
      'pack',
      'create',
    ];
    const shouldReject = ['cache', 'clean', 'pin', 'unpin', 'completion'];

    for (final cmd in shouldAccept) {
      test('$cmd accepts --offline', () async {
        final out = await runCli([cmd, '--help']);
        expect(out.exitCode, 0, reason: out.stderr);
        expect(
          out.stdout,
          contains('--offline'),
          reason: '$cmd should advertise --offline in --help',
        );
      });
    }

    for (final cmd in shouldReject) {
      test('$cmd does NOT accept --offline', () async {
        final out = await runCli([cmd, '--help']);
        expect(out.exitCode, 0, reason: out.stderr);
        expect(
          out.stdout,
          isNot(contains('--offline')),
          reason: '$cmd should not advertise --offline',
        );
      });
    }
  });
}
