// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.ComposeLayoutsTest
// (upstream pinned in UPSTREAM.md).
//
// Upstream builds this layout through the Compose-facing state/ API (State,
// ConstraintReference, Dimension), which is not ported. This port builds the
// same widgets with the core widget API instead: it makes the calls that
// state.apply(root) makes, in the same order, and keeps upstream's
// assertions unchanged.
//
// - State keeps its references in a HashMap, which visits them as parent,
//   divider, guideline, box. apply() creates each widget and adds it to the
//   root in that order (the guideline's reference is applied before it is
//   added), then applies every reference in that order.
// - A reference's widget is created from its Dimensions' values: 1 x 0 for
//   the divider and 0 x 0 for the box. The guideline reference creates its
//   Guideline as soon as verticalGuideline() is called.
// - Applying a reference applies its width and height Dimensions, then its
//   connections in ConstraintReference.applyWidgetConstraints order, then a
//   bias of 0.5 on both axes and VISIBLE. The Dimensions map as follows:
//   - createSuggested(WRAP_DIMENSION): MATCH_CONSTRAINT, MATCH_CONSTRAINT_WRAP;
//   - createWrap(), and the default createFixed(WRAP_DIMENSION) of the parent
//     and the guideline: WRAP_CONTENT;
//   - createFixed(1): FIXED, with a size of 1;
//   - createPercent(0, 0.8f).suggested(0): MATCH_CONSTRAINT,
//     MATCH_CONSTRAINT_PERCENT of 0.8 with a max of 0, which means none.
// - centerHorizontally(parent) is startToStart(parent) plus endToEnd(parent),
//   and centerVertically(parent) is topToTop(parent) plus
//   bottomToBottom(parent). State connects start and end to the left and
//   right anchors. The box's startToEnd("guideline") connects after its
//   startToStart(parent) and replaces it.
// - Upstream's measurer recognizes the box by its companion widget, the view
//   that setView("box") attaches. The engine does not port companion widgets,
//   so this measurer matches the debug name, which State.apply sets to the
//   same key.
//
// Run on upstream's Java engine at the pinned commit, this translation matches
// the State version call for call: the same widget configuration, the same
// measure calls, and the same frames.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

class _Measurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final horizontalBehavior = measure.horizontalBehavior;
    final verticalBehavior = measure.verticalBehavior;
    final horizontalDimension = measure.horizontalDimension;
    final verticalDimension = measure.verticalDimension;

    if (horizontalBehavior == DimensionBehaviour.fixed) {
      measure.measuredWidth = horizontalDimension;
    } else if (horizontalBehavior == DimensionBehaviour.matchConstraint) {
      measure.measuredWidth = horizontalDimension;
      if (widget.getDebugName() == 'box' &&
          // && measure.measuredWidth == 0
          measure.measureStrategy == Measure.SELF_DIMENSIONS) {
        measure.measuredWidth = 1080;
      }
    } else if (horizontalBehavior == DimensionBehaviour.wrapContent) {
      if (widget.getDebugName() == 'box') {
        measure.measuredWidth = 1080;
      }
    }
    if (verticalBehavior == DimensionBehaviour.fixed) {
      measure.measuredHeight = verticalDimension;
    } else if (verticalBehavior == DimensionBehaviour.wrapContent) {
      if (widget.getDebugName() == 'box') {
        measure.measuredHeight = measure.measuredWidth ~/ 2;
      }
    }
  }

  @override
  void didMeasures() {}
}

final _Measurer sMeasurer = _Measurer();

/// ConstraintReference.applyConnection: connects the [from] anchor of
/// [widget] to the [to] anchor of [target], with State's default margin and
/// gone margin (both 0), without forcing the connection.
void _applyConnection(
  ConstraintWidget widget,
  ConstraintAnchorType from,
  ConstraintWidget target,
  ConstraintAnchorType to,
) {
  widget.getAnchor(from)!.connect(target.getAnchor(to), 0, 0, false);
}

/// What applying the guideline's reference does: its GuidelineReference
/// facade sets the orientation and percent, then the reference applies its
/// default Dimensions, biases and visibility.
void _applyGuidelineReference(Guideline guideline) {
  guideline.setOrientation(Guideline.vertical);
  guideline.setGuidePercent(0.5);
  guideline.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
  guideline.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
  guideline.setHorizontalBiasPercent(0.5);
  guideline.setVerticalBiasPercent(0.5);
  guideline.setVisibility(ConstraintWidget.VISIBLE);
}

void main() {
  group('ComposeLayoutsTest', () {
    test('dividerMatchTextHeight_inWrapConstraintLayout_longText', () {
      const left = ConstraintAnchorType.left;
      const right = ConstraintAnchorType.right;
      const top = ConstraintAnchorType.top;
      const bottom = ConstraintAnchorType.bottom;

      // State state = new State(); its parent reference stands for the root.
      // state.verticalGuideline("guideline").percent(0.5f) creates the
      // Guideline now; state.constraints("box")... and
      // state.constraints("divider")... only record their constraints.
      final guideline = Guideline();
      final root = ConstraintWidgetContainer.rect(0, 0, 1080, 1977);

      // state.apply(root):
      root.removeAllChildren();
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      // Create and add the widgets: divider, guideline, box.
      final divider = ConstraintWidget.size(1, 0);
      divider.setDebugName('divider');
      divider.setParent(null);
      root.add(divider);
      guideline.setDebugName('guideline');
      guideline.setParent(null);
      _applyGuidelineReference(guideline);
      root.add(guideline);
      final box = ConstraintWidget.size(0, 0);
      box.setDebugName('box');
      box.setParent(null);
      root.add(box);
      // Apply every reference: parent, divider, guideline, box.
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setHorizontalBiasPercent(0.5);
      root.setVerticalBiasPercent(0.5);
      root.setVisibility(ConstraintWidget.VISIBLE);

      divider.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      divider.setWidth(1);
      divider.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      divider.setVerticalMatchStyle(
        ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
        0,
        0,
        0.8,
      );
      _applyConnection(divider, left, root, left); // START_TO_START
      _applyConnection(divider, right, root, right); // END_TO_END
      _applyConnection(divider, top, root, top); // TOP_TO_TOP
      _applyConnection(divider, bottom, root, bottom); // BOTTOM_TO_BOTTOM
      divider.setHorizontalBiasPercent(0.5);
      divider.setVerticalBiasPercent(0.5);
      divider.setVisibility(ConstraintWidget.VISIBLE);

      _applyGuidelineReference(guideline);

      box.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      box.setHorizontalMatchStyle(
        ConstraintWidget.MATCH_CONSTRAINT_WRAP,
        0,
        ConstraintWidget.intMaxValue,
        1,
      );
      box.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      _applyConnection(box, left, root, left); // START_TO_START
      _applyConnection(box, left, guideline, right); // START_TO_END
      _applyConnection(box, right, root, right); // END_TO_END
      _applyConnection(box, top, root, top); // TOP_TO_TOP
      _applyConnection(box, bottom, root, bottom); // BOTTOM_TO_BOTTOM
      box.setHorizontalBiasPercent(0.5);
      box.setVerticalBiasPercent(0.5);
      box.setVisibility(ConstraintWidget.VISIBLE);

      // Back in the test body.
      root.setWidth(1080);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      root.setDebugName('root');
      box.setDebugName('box');
      guideline.setDebugName('guideline');
      divider.setDebugName('divider');

      root.setMeasurer(sMeasurer);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      //root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.measure(root.getOptimizationLevel(), 0, 0, 0, 0, 0, 0, 0, 0);

      expect(box.getWidth(), root.getWidth() ~/ 2);
      expect(box.getHeight(), root.getWidth() ~/ 2 ~/ 2);
      expect(divider.getWidth(), 1);
      expect(divider.getHeight(), (box.getHeight() * 0.8).toInt());
    });
  });
}
