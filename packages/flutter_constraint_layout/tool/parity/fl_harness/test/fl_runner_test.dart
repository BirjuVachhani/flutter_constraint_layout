// FL runner entry (FORMATS.md section 11). Pass the corpus with
// --dart-define=FL_IN=<file> --dart-define=FL_OUT=<file>; optional FL_TAG,
// FL_SHARD/FL_SHARDS and FL_LIMIT.
import 'package:cl_fl_harness/fl_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FL runner', (tester) async {
    final config = FlRunConfig.fromEnvironment();
    if (config.input.isEmpty || config.output.isEmpty) {
      markTestSkipped('FL_IN and FL_OUT are not set');
      return;
    }
    final sw = Stopwatch()..start();
    final (laidOut, unmapped, errors) = await runFl(tester, config);
    // ignore: avoid_print
    print(
      'FL ${config.input} shard ${config.shard}/${config.shards}: laid out '
      '$laidOut, unmapped $unmapped, errors $errors, ${sw.elapsedMilliseconds} ms',
    );
  }, timeout: Timeout.none);
}
