// The Dart layout paths vfuzz runs (FORMATS.md sections 5, 17, 18 and 20).
//
//   core<level>  OpDriver's core path at that optimization level, e.g. core0,
//                core257, core64, core321 (vpaths_future.dart)
//   view<level>  VOpDriver's view path at that level, e.g. view0, view257,
//                view321 (vpaths_future.dart)
//
// The Phase 0 paths graphfirst and forced ran the graph-first entry
// ConstraintWidgetContainer.layoutGraphFirst() through the repo's
// test/support/solver_parity.dart; Phase 5a deletes both, so they are retired
// here.
//
// Every path replays the op list (L ops run one pass of the path), runs the
// implicit final pass, and reports OpDriver's geometry with a status.
import 'dart:async';

import 'package:constraint_engine/constraint_engine.dart';

import 'vpaths_future.dart' as future;

/// The outcome of one layout on one path.
class PathResult {
  PathResult(this.status, this.geometry, this.root, {this.childLayouts = 0});

  /// `ok`, `ok-printed`, or `EXC:<message>`.
  final String status;

  /// OpDriver's geometry string, with the `!status | ` prefix when the
  /// status is not ok.
  final String geometry;

  /// The laid-out container (for features and debugging).
  final ConstraintWidgetContainer root;

  /// Measure calls the path's view measurer made (0 on a core path).
  final int childLayouts;
}

/// A path: runs an op list.
typedef LayoutPath = PathResult Function(List<String> ops);

/// The path [name] (`core<level>` or `view<level>`), or null for an unknown
/// one. [measurer] is accepted for the command line's sake and unused: the
/// core paths measure with the echo measurer and the view paths with the
/// content model (FORMATS.md 5 and 20).
LayoutPath? pathNamed(String name, {String measurer = 'auto'}) =>
    future.futurePath(name);

/// Whether [name] is a path vfuzz accepts: `none` (the corpus only) or a
/// path of [pathNamed].
bool isPathName(String name) =>
    name == 'none' || future.futurePath(name) != null;

/// The path names, for usage messages.
const pathNames = ['none', 'core<level>', 'view<level>'];

/// Runs [body], returning whether it printed (the solver loop prints the
/// exceptions it catches) and what it threw (BL's bfuzz `guarded`).
(bool, Object?) guarded(void Function() body) {
  var printed = false;
  Object? thrown;
  runZoned(
    () {
      try {
        body();
      } catch (e) {
        thrown = e;
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        printed = true;
      },
    ),
  );
  return (printed, thrown);
}

/// Whether VOpDriver runs [ops] on its view path (-Dpath=auto, FORMATS.md
/// 8.1): the op list has a ct, cspec, cpad, cmin or cmax op.
bool isViewPathOps(List<String> ops) => ops.any(
  (o) =>
      o.startsWith('ct ') ||
      o.startsWith('cspec ') ||
      o.startsWith('cpad ') ||
      o.startsWith('cmin ') ||
      o.startsWith('cmax '),
);

/// OpDriver's geometry of [root] (the repo's geometryOf format), with every
/// child moved by ([dx], [dy]) and the root reported as [rootW] x [rootH].
/// A GONE child prints `gone, w x h`, except a barrier (BL's core rule) or,
/// with [viewRule], any guideline or helper (barrier, Flow), which
/// onLayout places anyway (VOpDriver v2's view rule, FORMATS.md 8.2).
String geometry(
  ConstraintWidgetContainer root, {
  int dx = 0,
  int dy = 0,
  int? rootW,
  int? rootH,
  bool viewRule = false,
}) {
  final sb = StringBuffer()
    ..write('root ${rootW ?? root.getWidth()} x ${rootH ?? root.getHeight()}');
  for (final (i, w) in root.getChildren().indexed) {
    final name = w.getDebugName() ?? '#$i';
    final placed = viewRule
        ? (w is Guideline || w is HelperWidget)
        : w is Barrier;
    if (w.getVisibility() == ConstraintWidget.GONE && !placed) {
      sb.write(' | $name: gone, ${w.getWidth()} x ${w.getHeight()}');
    } else {
      sb.write(
        ' | $name: (${w.getX() + dx}, ${w.getY() + dy}) '
        '${w.getWidth()} x ${w.getHeight()}',
      );
    }
  }
  return sb.toString();
}
