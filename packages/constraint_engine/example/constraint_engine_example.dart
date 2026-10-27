// A small tour of constraint_engine: describe a screen as widgets and the
// constraints between them, solve it, and print where everything ended up.
//
// Run it from packages/constraint_engine:
//
//   dart run example/constraint_engine_example.dart
//
// Anchor types and dimension behaviours are enums, so the calls below use
// Dart's dot shorthands: `.left` is `ConstraintAnchorType.left`.

import 'package:constraint_engine/constraint_engine.dart';

void main() {
  // The container is the root of the layout: here a fixed 400 x 300 area.
  final root = ConstraintWidgetContainer.sizeNamed('root', 400, 300);

  // 1. A fixed-size widget pinned to the top-left corner with 16 px margins.
  //    `fixed` is the default dimension behaviour, so the 48 x 48 passed to
  //    the constructor is its size.
  final logo = ConstraintWidget.sizeNamed('logo', 48, 48);
  logo.connect(.left, root, .left, 16);
  logo.connect(.top, root, .top, 16);

  // 2. A label that wraps its content: the measurer below reports its size.
  //    It sits 12 px right of the logo. Constraining its top to the logo's
  //    top and its bottom to the logo's bottom centers it on the logo.
  final title = ConstraintWidget.named('title');
  title.setHorizontalDimensionBehaviour(.wrapContent);
  title.setVerticalDimensionBehaviour(.wrapContent);
  title.connect(.left, logo, .right, 12);
  title.connect(.top, logo, .top);
  title.connect(.bottom, logo, .bottom);

  // 3. A match-constraint widget: its width is the space left between its
  //    left and right anchors (the container's edges, minus 16 px margins).
  //    Its height stays fixed at 40.
  final banner = ConstraintWidget.sizeNamed('banner', 0, 40);
  banner.setHorizontalDimensionBehaviour(.matchConstraint);
  banner.connect(.left, root, .left, 16);
  banner.connect(.right, root, .right, 16);
  banner.connect(.top, logo, .bottom, 16);

  // 4. Three buttons in a horizontal chain: neighbours are linked in both
  //    directions. The first widget is the chain head, and its chain style
  //    decides how the free space is shared: "spread inside" puts the end
  //    widgets against their anchors and spreads the rest evenly.
  final prev = ConstraintWidget.sizeNamed('prev', 80, 32);
  final play = ConstraintWidget.sizeNamed('play', 80, 32);
  final next = ConstraintWidget.sizeNamed('next', 80, 32);
  prev.connect(.left, root, .left, 16);
  prev.connect(.right, play, .left);
  play.connect(.left, prev, .right);
  play.connect(.right, next, .left);
  next.connect(.left, play, .right);
  next.connect(.right, root, .right, 16);
  prev.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
  for (final button in [prev, play, next]) {
    button.connect(.bottom, root, .bottom, 16);
  }

  // 5. A widget constrained on both sides of an axis is centered between
  //    them, and a bias moves it off-center: 0.25 puts a quarter of the free
  //    space on the left and three quarters on the right. Vertically it keeps
  //    the default bias of 0.5, centered between the banner and the buttons.
  final badge = ConstraintWidget.sizeNamed('badge', 64, 24);
  badge.connect(.left, root, .left);
  badge.connect(.right, root, .right);
  badge.setHorizontalBiasPercent(0.25);
  badge.connect(.top, banner, .bottom);
  badge.connect(.bottom, play, .top);

  root.addAll([logo, title, banner, prev, play, next, badge]);

  // The title wraps its content, so the engine has to ask the host how big
  // that content is: measure() asks the measurer for the size of the
  // children, then solves the layout (layout() alone measures nothing).
  root.setMeasurer(TextMeasurer({title: 'Pure Dart layout'}));

  measureLayout(root);
  printLayout(root);
  // Prints:
  //   400 x 300 container
  //     logo    x  16  y  16  w  48  h  48
  //     title   x  76  y  30  w 128  h  20
  //     banner  x  16  y  80  w 368  h  40
  //     prev    x  16  y 252  w  80  h  32
  //     play    x 160  y 252  w  80  h  32
  //     next    x 304  y 252  w  80  h  32
  //     badge   x  84  y 174  w  64  h  24
  //
  // How the numbers follow from the constraints:
  //   title:   x = 16 + 48 + 12; w = 16 characters * 8 px;
  //            y = 16 + (48 - 20) / 2, centered on the logo.
  //   banner:  w = 400 - 16 - 16; y = 16 + 48 + 16.
  //   buttons: y = 300 - 16 - 32. The ends sit 16 px from the edges, and play
  //            is centered in the 208 px between them (64 px on each side).
  //   badge:   x = 0.25 * (400 - 64); y = 120 + (132 - 24) / 2, centered
  //            between the banner's bottom (120) and the buttons' top (252).

  // The model is persistent: change it and lay it out again. Here the
  // container grows to 600 px wide. The banner stretches, the chain spreads
  // over the new width, and the badge keeps its bias.
  root.setWidth(600);
  measureLayout(root);
  printLayout(root);
  // Prints "600 x 300 container" and the same rectangles as before, except:
  //     banner  x  16  y  80  w 568  h  40
  //     play    x 260  y 252  w  80  h  32
  //     next    x 504  y 252  w  80  h  32
  //     badge   x 134  y 174  w  64  h  24
}

/// Measures widgets on behalf of the engine.
///
/// The engine calls [measure] whenever it needs a widget's size. A
/// wrap-content axis asks for the content's natural size. The engine sizes
/// every other axis itself and proposes that size, so the measurer echoes it
/// back.
class TextMeasurer implements Measurer {
  TextMeasurer(this.texts);

  /// The text each label widget displays.
  final Map<ConstraintWidget, String> texts;

  /// A fixed-pitch font: every character is 8 px wide, a line is 20 px tall.
  static const int charWidth = 8;
  static const int lineHeight = 20;

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    // The content's natural size: a label's text, or the size the widget
    // already has for anything that is not a label.
    final text = texts[widget];
    final naturalWidth = text == null
        ? widget.getWidth()
        : text.length * charWidth;
    final naturalHeight = text == null ? widget.getHeight() : lineHeight;

    measure.measuredWidth =
        measure.horizontalBehavior == DimensionBehaviour.wrapContent
        ? naturalWidth
        : measure.horizontalDimension;
    measure.measuredHeight =
        measure.verticalBehavior == DimensionBehaviour.wrapContent
        ? naturalHeight
        : measure.verticalDimension;

    // The engine reuses its Measure objects from call to call, so set every
    // output, the baseline included. A real text measurer would report the
    // distance from the top of the text to its baseline here.
    measure.measuredBaseline = 0;
    measure.measuredHasBaseline = false;
  }

  // Called after measure() has measured the children; this measurer keeps
  // no per-batch state, so there is nothing to do.
  @override
  void didMeasures() {}
}

/// Measures and lays out [root] at its own size, as Android's ConstraintLayout
/// does when its parent gives it an exact size: [BasicMeasure.EXACTLY] on
/// both axes, at the container's optimization level.
void measureLayout(ConstraintWidgetContainer root) {
  root.measure(
    root.getOptimizationLevel(),
    BasicMeasure.EXACTLY,
    root.getWidth(),
    BasicMeasure.EXACTLY,
    root.getHeight(),
    0,
    0,
    0,
    0,
  );
}

/// Prints the solved rectangle of every widget in [root].
void printLayout(ConstraintWidgetContainer root) {
  String pad(int value) => value.toString().padLeft(3);
  print('${root.getWidth()} x ${root.getHeight()} container');
  for (final widget in root.getChildren()) {
    final name = (widget.getDebugName() ?? '?').padRight(6);
    print(
      '  $name  x ${pad(widget.getX())}  y ${pad(widget.getY())}  '
      'w ${pad(widget.getWidth())}  h ${pad(widget.getHeight())}',
    );
  }
  print('');
}
