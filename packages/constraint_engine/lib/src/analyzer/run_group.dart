// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.RunGroup

import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import 'chain_run.dart';
import 'dependency_node.dart';
import 'helper_references.dart';
import 'horizontal_widget_run.dart';
import 'vertical_widget_run.dart';
import 'widget_run.dart';

class RunGroup {
  static const int start = 0;
  static const int end = 1;
  static const int baseline = 2;

  static int index = 0;

  int position = 0;
  bool dual = false;

  WidgetRun? mFirstRun;
  WidgetRun? mLastRun;
  final List<WidgetRun> mRuns = [];

  int mGroupIndex = 0;
  int mDirection;

  RunGroup(WidgetRun run, this.mDirection) {
    mGroupIndex = index;
    index++;
    mFirstRun = run;
    mLastRun = run;
  }

  void add(WidgetRun run) {
    mRuns.add(run);
    mLastRun = run;
  }

  /// Whether the last [computeWrapSize] reached a node it was already inside
  /// of. Upstream's traversals recurse until the stack overflows on such a
  /// loop, which runs that depend on each other form (for example a widget
  /// centered between the parent's left and a sibling's right, whose left is
  /// linked to the widget's right). Once set, the traversals stop at once.
  bool _cycle = false;

  /// Starts visiting [node]: false, and the traversal must stop, when the
  /// traversal is already inside [node] or found a loop before.
  bool _enter(DependencyNode node) {
    if (_cycle || node.traversing) {
      _cycle = true;
      return false;
    }
    node.traversing = true;
    return true;
  }

  int _traverseStart(DependencyNode node, int startPosition) {
    final run = node.mRun;
    if (run is HelperReferences) {
      return startPosition;
    }
    if (!_enter(node)) {
      return startPosition;
    }
    var position = startPosition;

    final count = node.mDependencies.length;
    for (var i = 0; i < count; i++) {
      final dependency = node.mDependencies[i];
      if (dependency is DependencyNode) {
        final nextNode = dependency;
        if (nextNode.mRun == run) {
          continue;
        }
        position = _max(
          position,
          _traverseStart(nextNode, startPosition + nextNode.mMargin),
        );
      }
    }

    if (node == run.start) {
      final dimension = run.getWrapDimension();
      position = _max(
        position,
        _traverseStart(run.end, startPosition + dimension),
      );
      position = _max(position, startPosition + dimension - run.end.mMargin);
    }

    node.traversing = false;
    return position;
  }

  int _traverseEnd(DependencyNode node, int startPosition) {
    final run = node.mRun;
    if (run is HelperReferences) {
      return startPosition;
    }
    if (!_enter(node)) {
      return startPosition;
    }
    var position = startPosition;

    final count = node.mDependencies.length;
    for (var i = 0; i < count; i++) {
      final dependency = node.mDependencies[i];
      if (dependency is DependencyNode) {
        final nextNode = dependency;
        if (nextNode.mRun == run) {
          continue;
        }
        position = _min(
          position,
          _traverseEnd(nextNode, startPosition + nextNode.mMargin),
        );
      }
    }

    if (node == run.end) {
      final dimension = run.getWrapDimension();
      position = _min(
        position,
        _traverseEnd(run.start, startPosition - dimension),
      );
      position = _min(position, startPosition - dimension - run.start.mMargin);
    }

    node.traversing = false;
    return position;
  }

  /// The size this group needs along [orientation] in a wrap-content
  /// [container], or null when its runs depend on each other in a loop (see
  /// [_cycle]), which the graph cannot resolve.
  int? computeWrapSize(ConstraintWidgetContainer container, int orientation) {
    _cycle = false;
    final first = mFirstRun!;
    if (first is ChainRun) {
      if (first.orientation != orientation) {
        return 0;
      }
    } else {
      if (orientation == ConstraintWidget.HORIZONTAL) {
        if (first is! HorizontalWidgetRun) {
          return 0;
        }
      } else {
        if (first is! VerticalWidgetRun) {
          return 0;
        }
      }
    }
    final containerStart = orientation == ConstraintWidget.HORIZONTAL
        ? container.mHorizontalRun!.start
        : container.mVerticalRun!.start;
    final containerEnd = orientation == ConstraintWidget.HORIZONTAL
        ? container.mHorizontalRun!.end
        : container.mVerticalRun!.end;

    final runWithStartTarget = first.start.mTargets.contains(containerStart);
    final runWithEndTarget = first.end.mTargets.contains(containerEnd);

    var dimension = first.getWrapDimension();

    if (runWithStartTarget && runWithEndTarget) {
      final maxPosition = _traverseStart(first.start, 0);
      final minPosition = _traverseEnd(first.end, 0);

      var endGap = maxPosition - dimension;
      if (endGap >= -first.end.mMargin) {
        endGap += first.end.mMargin;
      }
      var startGap = -minPosition - dimension - first.start.mMargin;
      if (startGap >= first.start.mMargin) {
        startGap -= first.start.mMargin;
      }
      final bias = first.mWidget.getBiasPercent(orientation);
      var gap = 0;
      if (bias > 0) {
        // A bias of exactly 1 divides by zero here: NaN when the end gap is
        // 0, infinite otherwise. Upstream's (long) casts turn those into 0
        // and a saturated value; Dart's toInt() would throw.
        gap = _toJavaLong((startGap / bias) + (endGap / (1 - bias)));
      }

      startGap = _toJavaLong(0.5 + gap * bias);
      endGap = _toJavaLong(0.5 + gap * (1 - bias));

      final runDimension = startGap + dimension + endGap;
      dimension = first.start.mMargin + runDimension - first.end.mMargin;
    } else if (runWithStartTarget) {
      final maxPosition = _traverseStart(first.start, first.start.mMargin);
      final runDimension = first.start.mMargin + dimension;
      dimension = _max(maxPosition, runDimension);
    } else if (runWithEndTarget) {
      final minPosition = _traverseEnd(first.end, first.end.mMargin);
      final runDimension = -first.end.mMargin + dimension;
      dimension = _max(-minPosition, runDimension);
    } else {
      dimension =
          first.start.mMargin + first.getWrapDimension() - first.end.mMargin;
    }

    return _cycle ? null : dimension;
  }

  bool _defineTerminalWidget(WidgetRun run, int orientation) {
    if (!run.mWidget.isTerminalWidget[orientation]) {
      return false;
    }
    for (final dependency in run.start.mDependencies) {
      if (dependency is DependencyNode) {
        final node = dependency;
        if (node.mRun == run) {
          continue;
        }
        if (node == node.mRun.start) {
          if (run is ChainRun) {
            for (final widgetChainRun in run.mWidgets) {
              _defineTerminalWidget(widgetChainRun, orientation);
            }
          } else {
            if (run is! HelperReferences) {
              run.mWidget.isTerminalWidget[orientation] = false;
            }
          }
          _defineTerminalWidget(node.mRun, orientation);
        }
      }
    }
    for (final dependency in run.end.mDependencies) {
      if (dependency is DependencyNode) {
        final node = dependency;
        if (node.mRun == run) {
          continue;
        }
        if (node == node.mRun.start) {
          if (run is ChainRun) {
            for (final widgetChainRun in run.mWidgets) {
              _defineTerminalWidget(widgetChainRun, orientation);
            }
          } else {
            if (run is! HelperReferences) {
              run.mWidget.isTerminalWidget[orientation] = false;
            }
          }
          _defineTerminalWidget(node.mRun, orientation);
        }
      }
    }
    return false;
  }

  void defineTerminalWidgets(bool horizontalCheck, bool verticalCheck) {
    final first = mFirstRun;
    if (horizontalCheck && first is HorizontalWidgetRun) {
      _defineTerminalWidget(first, ConstraintWidget.HORIZONTAL);
    }
    if (verticalCheck && first is VerticalWidgetRun) {
      _defineTerminalWidget(first, ConstraintWidget.VERTICAL);
    }
  }

  static int _max(int a, int b) => a > b ? a : b;
  static int _min(int a, int b) => a < b ? a : b;

  /// Java's narrowing conversion of a floating-point value to `long` (JLS
  /// 5.1.3), which upstream's `(long)` casts rely on: NaN converts to 0 and
  /// an infinite value saturates, where Dart's toInt() throws for both.
  /// Finite values convert as toInt() does, toward zero.
  static int _toJavaLong(double value) {
    if (value.isNaN) return 0;
    if (value.isInfinite) {
      // On the VM, toInt() saturates a finite value at the 64-bit bounds,
      // which are Java's Long.MIN_VALUE and Long.MAX_VALUE.
      return (value > 0 ? double.maxFinite : -double.maxFinite).toInt();
    }
    return value.toInt();
  }
}
