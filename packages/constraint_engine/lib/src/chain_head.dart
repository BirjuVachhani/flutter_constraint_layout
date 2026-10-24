// Copyright (C) 2018 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.ChainHead (upstream
// pinned in UPSTREAM.md).

import 'constraint_widget.dart';

/// Class to represent a chain by its main elements.
class ChainHead {
  ConstraintWidget mFirst;
  ConstraintWidget? mFirstVisibleWidget;
  late ConstraintWidget mLast;
  ConstraintWidget? mLastVisibleWidget;
  ConstraintWidget? mHead;
  ConstraintWidget? mFirstMatchConstraintWidget;
  ConstraintWidget? mLastMatchConstraintWidget;
  List<ConstraintWidget>? mWeightedMatchConstraintsWidgets;
  int mWidgetsCount = 0;
  int mWidgetsMatchCount = 0;
  double mTotalWeight = 0;
  int mVisibleWidgets = 0;
  int mTotalSize = 0;
  int mTotalMargins = 0;
  bool mOptimizable = false;
  final int _orientation;
  final bool _isRtl;
  bool mHasUndefinedWeights = false;
  bool mHasDefinedWeights = false;
  bool mHasComplexMatchWeights = false;
  bool mHasRatio = false;
  bool _defined = false;

  /// [first] is the first widget in the chain; [orientation] is HORIZONTAL or
  /// VERTICAL; [isRtl] determines the actual head of a horizontal chain.
  ChainHead(ConstraintWidget first, int orientation, bool isRtl)
      : mFirst = first,
        _orientation = orientation,
        _isRtl = isRtl;

  /// True if the widget should be part of the match equality rules in the
  /// chain.
  static bool _isMatchConstraintEqualityCandidate(
      ConstraintWidget widget, int orientation) {
    return widget.getVisibility() != ConstraintWidget.GONE &&
        widget.mListDimensionBehaviors[orientation] ==
            DimensionBehaviour.matchConstraint &&
        (widget.mResolvedMatchConstraintDefault[orientation] ==
                ConstraintWidget.MATCH_CONSTRAINT_SPREAD ||
            widget.mResolvedMatchConstraintDefault[orientation] ==
                ConstraintWidget.MATCH_CONSTRAINT_RATIO);
  }

  void _defineChainProperties() {
    final offset = _orientation * 2;
    var lastVisited = mFirst;
    mOptimizable = true;

    // TraverseChain
    var widget = mFirst;
    ConstraintWidget? next = mFirst;
    var done = false;
    while (!done) {
      mWidgetsCount++;
      widget.mNextChainWidget[_orientation] = null;
      widget.mListNextMatchConstraintsWidget[_orientation] = null;
      if (widget.getVisibility() != ConstraintWidget.GONE) {
        mVisibleWidgets++;
        if (widget.getDimensionBehaviour(_orientation) !=
            DimensionBehaviour.matchConstraint) {
          mTotalSize += widget.getLength(_orientation);
        }
        mTotalSize += widget.mListAnchors[offset].getMargin();
        mTotalSize += widget.mListAnchors[offset + 1].getMargin();
        mTotalMargins += widget.mListAnchors[offset].getMargin();
        mTotalMargins += widget.mListAnchors[offset + 1].getMargin();
        // Visible widgets linked list.
        mFirstVisibleWidget ??= widget;
        mLastVisibleWidget = widget;

        // Match constraint linked list.
        if (widget.mListDimensionBehaviors[_orientation] ==
            DimensionBehaviour.matchConstraint) {
          if (widget.mResolvedMatchConstraintDefault[_orientation] ==
                  ConstraintWidget.MATCH_CONSTRAINT_SPREAD ||
              widget.mResolvedMatchConstraintDefault[_orientation] ==
                  ConstraintWidget.MATCH_CONSTRAINT_RATIO ||
              widget.mResolvedMatchConstraintDefault[_orientation] ==
                  ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
            mWidgetsMatchCount++;
            final weight = widget.mWeight[_orientation];
            if (weight > 0) {
              mTotalWeight += widget.mWeight[_orientation];
            }

            if (_isMatchConstraintEqualityCandidate(widget, _orientation)) {
              if (weight < 0) {
                mHasUndefinedWeights = true;
              } else {
                mHasDefinedWeights = true;
              }
              mWeightedMatchConstraintsWidgets ??= <ConstraintWidget>[];
              mWeightedMatchConstraintsWidgets!.add(widget);
            }

            mFirstMatchConstraintWidget ??= widget;
            if (mLastMatchConstraintWidget != null) {
              mLastMatchConstraintWidget!
                  .mListNextMatchConstraintsWidget[_orientation] = widget;
            }
            mLastMatchConstraintWidget = widget;
          }
          if (_orientation == ConstraintWidget.HORIZONTAL) {
            if (widget.mMatchConstraintDefaultWidth !=
                ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
              mOptimizable = false;
            } else if (widget.mMatchConstraintMinWidth != 0 ||
                widget.mMatchConstraintMaxWidth != 0) {
              mOptimizable = false;
            }
          } else {
            if (widget.mMatchConstraintDefaultHeight !=
                ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
              mOptimizable = false;
            } else if (widget.mMatchConstraintMinHeight != 0 ||
                widget.mMatchConstraintMaxHeight != 0) {
              mOptimizable = false;
            }
          }
          if (widget.mDimensionRatio != 0.0) {
            mOptimizable = false;
            mHasRatio = true;
          }
        }
      }
      if (!identical(lastVisited, widget)) {
        lastVisited.mNextChainWidget[_orientation] = widget;
      }
      lastVisited = widget;

      // go to the next widget
      final nextAnchor = widget.mListAnchors[offset + 1].mTarget;
      if (nextAnchor != null) {
        next = nextAnchor.mOwner;
        if (next.mListAnchors[offset].mTarget == null ||
            !identical(next.mListAnchors[offset].mTarget!.mOwner, widget)) {
          next = null;
        }
      } else {
        next = null;
      }
      if (next != null) {
        widget = next;
      } else {
        done = true;
      }
    }
    if (mFirstVisibleWidget != null) {
      mTotalSize -= mFirstVisibleWidget!.mListAnchors[offset].getMargin();
    }
    if (mLastVisibleWidget != null) {
      mTotalSize -= mLastVisibleWidget!.mListAnchors[offset + 1].getMargin();
    }
    mLast = widget;

    if (_orientation == ConstraintWidget.HORIZONTAL && _isRtl) {
      mHead = mLast;
    } else {
      mHead = mFirst;
    }

    mHasComplexMatchWeights = mHasDefinedWeights && mHasUndefinedWeights;
  }

  ConstraintWidget getFirst() => mFirst;

  ConstraintWidget? getFirstVisibleWidget() => mFirstVisibleWidget;

  ConstraintWidget getLast() => mLast;

  ConstraintWidget? getLastVisibleWidget() => mLastVisibleWidget;

  ConstraintWidget? getHead() => mHead;

  ConstraintWidget? getFirstMatchConstraintWidget() => mFirstMatchConstraintWidget;

  ConstraintWidget? getLastMatchConstraintWidget() => mLastMatchConstraintWidget;

  double getTotalWeight() => mTotalWeight;

  void define() {
    if (!_defined) {
      _defineChainProperties();
    }
    _defined = true;
  }
}
