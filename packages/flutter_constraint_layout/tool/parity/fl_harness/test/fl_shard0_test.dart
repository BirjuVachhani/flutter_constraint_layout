// FL runner, shard 0 of 2 (run both with --concurrency=2; run_fl.sh does).
// Output goes to <FL_OUT>.0 (and .dry/.fresh beside it); FL_IN, FL_OUT,
// FL_TAG, FL_DRY, FL_INPLACE and FL_LIMIT as in lib/fl_runner.dart.
import 'package:cl_fl_harness/fl_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FL runner shard 0/2', (tester) async {
    final env = FlRunConfig.fromEnvironment();
    if (env.input.isEmpty || env.output.isEmpty) {
      markTestSkipped('FL_IN and FL_OUT are not set');
      return;
    }
    final config = env.forShard(0, 2);
    final sw = Stopwatch()..start();
    final (laidOut, unmapped, errors) = await runFl(tester, config);
    // ignore: avoid_print
    print(
      'FL ${config.input} shard 0/2: laid out $laidOut, unmapped '
      '$unmapped, errors $errors, ${sw.elapsedMilliseconds} ms',
    );
  }, timeout: Timeout.none);
}
