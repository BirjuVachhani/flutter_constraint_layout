// bbench: per-layout engine cost on a sample of the parity corpus R. BL is
// the baseline suite this benchmark comes from, which timed the previous
// release's graph-first engine (its route field: the graph kept or declined
// the layout) and upstream's Java engine (JTimer). BL's sampling (per file, every ceil(lines / perFile)-th
// layout; 4,781 layouts at perFile 300 on BL's 16 corpus files) and BL's
// timing (each layout built once per path, one warm-up measure, then the
// median of [reps] measures of the same container, in ns) are kept. The
// retired paths (G, S, E, Dm, Sx, Ex) are replaced by:
//
//   M257  ConstraintWidgetContainer.measure at 257 with VOpDriver's Echo: the
//         oracle's core257 path, as BL's JTimer measures Java (specs from the
//         root's wrap flags and size before the first measure)
//   M0    the same at level 0 (the solver alone, BL's Sx)
//   M321  the same at 321 (the graph first where Android's rules let it run)
//   V257  with --vr: ViewHost.measure at 257 on the VR2 layout of the same
//         id (R with content), the oracle's view257 path; each measure first
//         re-applies the FIXED sizes the op list configured, as the adapter's
//         model sync does
//
// Groups: kept and declined by BL's route field (K: the graph kept the
// layout in BL's graph-first run), per corpus half (bar, nob) and per file;
// with --complete, Direct-complete (every axis resolved by Direct, from a
// --direct dump of the same corpus at 257) against the rest.
//
//   bbench6 <perFile> <reps> [--paths M257,M0,M321] [--ref <core257.isg.gz>]
//           [--complete <ids>] [--vr <VR2.in>] [--vrref <view257.isg.gz>]
//           [--vrcomplete <ids>] <corpus files...>
// --ref checks every sampled layout's M257 geometry against a reference
// (an R.core257.isg.gz of gates/ref_runs.sh); --vrref the same for V257.
// The corpus files are R split per generator, in R's order, named
// bar_<gen>.txt for the 8 barrier generators and nob_<gen>.txt for the 8
// others (BL's 16 files): at perFile 300 they give BL's 4,781 layouts. The
// kept and declined groups need BL's route field (the third field of BL's
// files); on vfuzz lines that field is the path, so only the totals mean
// anything there.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:constraint_engine/constraint_engine.dart';

import '../dart/ops.dart';
import '../dart/vpaths.dart' show geometry;
import '../dart/vpaths_future.dart'
    show ContentViewMeasurer, EchoMeasurer, configuredSizes, reapplyFixedSizes;

int medianOf(List<int> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

/// BL's timeIt: one call, then the median of [reps] calls, in ns.
int timeIt(int reps, void Function() f) {
  final sw = Stopwatch();
  final samples = List<int>.filled(reps, 0);
  f();
  for (var i = 0; i < reps; i++) {
    sw
      ..reset()
      ..start();
    f();
    sw.stop();
    samples[i] = sw.elapsedTicks;
  }
  final freq = Stopwatch().frequency;
  return medianOf(samples) * 1000000000 ~/ freq;
}

/// Runs [body] with print captured (the solver loop prints what it catches);
/// returns what it threw.
Object? quiet(void Function() body) {
  Object? thrown;
  runZoned(() {
    try {
      body();
    } catch (e) {
      thrown = e;
    }
  }, zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}));
  return thrown;
}

/// The core path at [level] on [ops]: the built container and its measure,
/// with JTimer's specs (the root's wrap flags and size after the op list, read
/// once). The caller's first call is vfuzz `core<level>`'s final measure.
(ConstraintWidgetContainer, void Function()) buildCore(
  List<String> ops,
  int level,
) {
  final (w, h) = rootSize(ops);
  final root = ConstraintWidgetContainer.rect(0, 0, w, h)..setDebugName('root');
  void pass() {
    final wrapW =
        root.getHorizontalDimensionBehaviour() ==
        DimensionBehaviour.wrapContent;
    final wrapH =
        root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;
    root
      ..setMeasurer(const EchoMeasurer())
      ..setOptimizationLevel(level)
      ..measure(
        level,
        wrapW ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY,
        root.getWidth(),
        wrapH ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY,
        root.getHeight(),
        0,
        0,
        0,
        0,
      );
  }

  applyOps(root, ops, layoutPass: pass);
  // JTimer's specs: read once, before the first timed measure.
  final wrapW =
      root.getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent;
  final wrapH =
      root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;
  final wm = wrapW ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY;
  final hm = wrapH ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY;
  final cw = root.getWidth(), ch = root.getHeight();
  root
    ..setMeasurer(const EchoMeasurer())
    ..setOptimizationLevel(level);
  return (root, () => root.measure(level, wm, cw, hm, ch, 0, 0, 0, 0));
}

/// The view path at 257 on [ops] (the oracle's view257): the container, the
/// host and its measure (FIXED sizes re-applied first; the specs read once,
/// after the op list). The caller's first call is vfuzz view257's final
/// measure.
(ConstraintWidgetContainer, ViewHost, void Function()) buildView(
  List<String> ops,
) {
  final (w, h) = rootSize(ops);
  final root = ConstraintWidgetContainer.rect(0, 0, w, h)..setDebugName('root');
  final host = ViewHost(root, ContentViewMeasurer())
    ..optimizationLevel = Optimizer.OPTIMIZATION_STANDARD;
  final sizes = configuredSizes(ops);
  late int ws, hs;
  void specs() {
    final v = viewOf(root);
    host
      ..paddingLeft = v.padLeft
      ..paddingTop = v.padTop
      ..paddingRight = v.padRight
      ..paddingBottom = v.padBottom
      ..minWidth = v.minWidth
      ..minHeight = v.minHeight
      ..maxWidth = v.maxWidth
      ..maxHeight = v.maxHeight;
    final spec = v.spec;
    if (spec != null) {
      ws = MeasureSpec.makeMeasureSpec(spec.wSize, spec.wMode);
      hs = MeasureSpec.makeMeasureSpec(spec.hSize, spec.hMode);
    } else {
      ws =
          root.getHorizontalDimensionBehaviour() ==
              DimensionBehaviour.wrapContent
          ? MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
          : MeasureSpec.makeMeasureSpec(root.getWidth(), MeasureSpec.EXACTLY);
      hs =
          root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent
          ? MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
          : MeasureSpec.makeMeasureSpec(root.getHeight(), MeasureSpec.EXACTLY);
    }
  }

  applyOps(
    root,
    ops,
    layoutPass: () {
      specs();
      host.measure(ws, hs);
    },
  );
  specs();
  return (
    root,
    host,
    () {
      reapplyFixedSizes(root, sizes);
      host.measure(ws, hs);
    },
  );
}

class Acc {
  final t = <String, List<int>>{};
  int n = 0;
  int widgets = 0;
}

String us(int ns) => (ns / 1000).toStringAsFixed(1);

Map<String, String> readIsg(String path, Set<String> ids) {
  final out = <String, String>{};
  final lines = const LineSplitter().convert(
    utf8.decode(gzip.decode(File(path).readAsBytesSync())),
  );
  for (final l in lines) {
    final p = l.split('\t');
    if (ids.contains(p[0])) out[p[0]] = p.length > 2 ? p[2] : '';
  }
  return out;
}

Set<String> readIds(String path) =>
    File(path).readAsLinesSync().where((l) => l.isNotEmpty).toSet();

void main(List<String> args) {
  final perFile = int.parse(args[0]);
  final reps = int.parse(args[1]);
  var pathNames = ['M257', 'M0', 'M321'];
  String? refPath, completePath, vrPath, vrRefPath, vrCompletePath;
  final files = <String>[];
  for (var i = 2; i < args.length; i++) {
    switch (args[i]) {
      case '--paths':
        pathNames = args[++i].split(',');
      case '--ref':
        refPath = args[++i];
      case '--complete':
        completePath = args[++i];
      case '--vr':
        vrPath = args[++i];
      case '--vrref':
        vrRefPath = args[++i];
      case '--vrcomplete':
        vrCompletePath = args[++i];
      default:
        files.add(args[i]);
    }
  }
  const levels = {'M257': 257, 'M0': 0, 'M321': 321};
  for (final p in pathNames) {
    if (!levels.containsKey(p)) throw ArgumentError('path $p');
  }
  // The sample: BL's per-file stride.
  final sample =
      <(String file, String set, String id, String route, List<String> ops)>[];
  for (final fn in files) {
    final lines = File(
      fn,
    ).readAsLinesSync().where((l) => !l.startsWith('#')).toList();
    final step = (lines.length / perFile).ceil().clamp(1, 1 << 30);
    final name = fn.split('/').last;
    final set = name.split('_').first;
    for (var i = 0; i < lines.length; i += step) {
      final p = lines[i].split('\t');
      sample.add((name, set, p[0], p[2], p.last.split(';')));
    }
  }
  final ids = {for (final s in sample) s.$3};
  final ref = refPath == null ? null : readIsg(refPath, ids);
  final complete = completePath == null ? null : readIds(completePath);
  Map<String, List<String>>? vrOps;
  if (vrPath != null) {
    vrOps = {};
    for (final l in File(vrPath).readAsLinesSync()) {
      final tab = l.indexOf('\t');
      final id = l.substring(0, tab);
      final base = id.substring(id.indexOf('-') + 1);
      if (ids.contains(base)) vrOps[base] = l.split('\t').last.split(';');
    }
  }
  final vrRef = vrRefPath == null
      ? null
      : readIsg(vrRefPath, {for (final id in ids) 'VR2-$id'});
  final vrComplete = vrCompletePath == null ? null : readIds(vrCompletePath);
  final allPaths = [...pathNames, if (vrOps != null) 'V257'];

  final accs = <String, Acc>{};
  var refChecked = 0, refDiffer = 0, vrChecked = 0, vrDiffer = 0, failed = 0;
  final sw = Stopwatch()..start();
  for (final (file, set, id, route, ops) in sample) {
    final times = <String, int>{};
    var widgets = 0;
    var ok = true;
    for (final p in pathNames) {
      final thrown = quiet(() {
        final (root, measure) = buildCore(ops, levels[p]!);
        widgets = root.getChildren().length;
        measure();
        if (p == 'M257' && ref != null) {
          final want = ref[id];
          if (want != null) {
            refChecked++;
            if (geometry(root) != want) refDiffer++;
          }
        }
        times[p] = timeIt(reps, measure);
      });
      if (thrown != null) ok = false;
    }
    if (vrOps != null) {
      final vops = vrOps[id];
      if (vops == null) {
        ok = false;
      } else {
        final thrown = quiet(() {
          final (root, host, measure) = buildView(vops);
          measure();
          if (vrRef != null) {
            final want = vrRef['VR2-$id'];
            if (want != null) {
              vrChecked++;
              final got = geometry(
                root,
                viewRule: true,
                rootW: host.getMeasuredWidth(),
                rootH: host.getMeasuredHeight(),
              );
              if (got != want) vrDiffer++;
            }
          }
          times['V257'] = timeIt(reps, measure);
        });
        if (thrown != null) ok = false;
      }
    }
    if (!ok) {
      failed++;
      continue;
    }
    final r = route == 'K' ? 'kept' : 'declined';
    final keys = ['ALL', 'ALL $r', '$set ALL', '$set $r', 'file $file'];
    if (complete != null) {
      keys.add(
        complete.contains(id) ? 'ALL Direct-complete' : 'ALL not complete',
      );
    }
    if (vrComplete != null) {
      keys.add(
        vrComplete.contains('VR2-$id')
            ? 'ALL VR2 Direct-complete'
            : 'ALL VR2 not complete',
      );
    }
    for (final k in keys) {
      final a = accs[k] ??= Acc();
      for (final p in allPaths) {
        (a.t[p] ??= []).add(times[p]!);
      }
      a.n++;
      a.widgets += widgets;
    }
  }
  print(
    'bbench6: ${sample.length} sampled, $failed failed (threw), '
    'reps $reps, ${sw.elapsedMilliseconds} ms'
    '${ref == null ? '' : '; M257 geometry vs ref: $refChecked checked, $refDiffer differ'}'
    '${vrRef == null ? '' : '; V257 geometry vs ref: $vrChecked checked, $vrDiffer differ'}',
  );
  int sum(List<int> xs) => xs.fold(0, (p, x) => p + x);
  for (final k in accs.keys.toList()..sort()) {
    final a = accs[k]!;
    final sb = StringBuffer(
      '${k.padRight(28)} n ${a.n.toString().padLeft(5)}  widgets/layout '
      '${(a.widgets / a.n).toStringAsFixed(1).padLeft(5)}  median us:',
    );
    for (final p in allPaths) {
      sb.write(' $p ${us(medianOf(a.t[p]!)).padLeft(7)}');
    }
    sb.write('   total ms:');
    for (final p in allPaths) {
      sb.write(' $p ${(sum(a.t[p]!) / 1e6).toStringAsFixed(1)}');
    }
    print(sb);
  }
}
