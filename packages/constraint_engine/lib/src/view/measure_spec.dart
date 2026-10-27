// Copyright (C) 2006 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from AOSP android.view.View.MeasureSpec, View.resolveSizeAndState and
// ViewGroup.getChildMeasureSpec: the framework helpers the view layer of
// ConstraintLayout (androidx.constraintlayout.widget.ConstraintLayout, "CL"
// below; upstream pinned in UPSTREAM.md) measures its children and itself
// with. The upstream mirror does not contain the framework; the behaviour
// here is AOSP's at targetSdk 23 and later.

/// Android's `View.MeasureSpec`, with the framework helpers ConstraintLayout's
/// view layer uses on it.
///
/// A measure spec packs a mode and a size into a Java `int`: the mode in the
/// top two bits ([UNSPECIFIED], [EXACTLY] or [AT_MOST]) and the size in the
/// low 30 bits. Java's `int` is 32 bits, and [AT_MOST] is negative there; a
/// Dart spec holds the same 32 bits as an unsigned value, so [AT_MOST] is
/// `0x80000000`, the value of `BasicMeasure.AT_MOST`. Every function here
/// accepts either form and returns the unsigned one.
///
/// These are static members of a class with no instances, not top-level
/// names, so they cannot clash with a host's own measure types.
abstract final class MeasureSpec {
  /// The bit position of the mode in a spec.
  static const int MODE_SHIFT = 30;

  /// The mode bits of a spec.
  static const int MODE_MASK = 0xC0000000;

  /// The size bits of a spec (Java's `~MODE_MASK`).
  static const int _SIZE_MASK = 0x3FFFFFFF;

  /// The parent imposes no constraint on the child (`BasicMeasure.UNSPECIFIED`).
  static const int UNSPECIFIED = 0;

  /// The child is exactly the spec's size (`BasicMeasure.EXACTLY`).
  static const int EXACTLY = 0x40000000;

  /// The child is at most the spec's size (`BasicMeasure.AT_MOST`).
  static const int AT_MOST = 0x80000000;

  /// `View.MEASURED_SIZE_MASK`: the size bits of a measured dimension, which
  /// `View.getMeasuredWidth` and `getMeasuredHeight` keep.
  static const int MEASURED_SIZE_MASK = 0x00FFFFFF;

  /// `View.MEASURED_STATE_MASK`: the state bits of a measured dimension.
  static const int MEASURED_STATE_MASK = 0xFF000000;

  /// `View.MEASURED_STATE_TOO_SMALL`: the state bit of a view measured
  /// smaller than it wants to be.
  static const int MEASURED_STATE_TOO_SMALL = 0x01000000;

  /// `View.MEASURED_HEIGHT_STATE_SHIFT`: where the height's state bits go in
  /// a combined measured state.
  static const int MEASURED_HEIGHT_STATE_SHIFT = 16;

  /// `View.sUseZeroUnspecifiedMeasureSpec`: false for apps targeting API 23
  /// and later, whose UNSPECIFIED child specs carry the parent's size.
  static const bool USE_ZERO_UNSPECIFIED_MEASURE_SPEC = false;

  /// `MeasureSpec.makeMeasureSpec(size, mode)`:
  /// `(size & ~MODE_MASK) | (mode & MODE_MASK)` on 32 bits.
  ///
  /// A negative [size] corrupts the spec exactly as it does in Java: its low
  /// 30 bits become the size.
  static int makeMeasureSpec(int size, int mode) =>
      (size & _SIZE_MASK) | (mode & MODE_MASK);

  /// `MeasureSpec.getMode(measureSpec)`: [UNSPECIFIED], [EXACTLY], [AT_MOST],
  /// or `0xC0000000` for a corrupted spec.
  static int getMode(int measureSpec) => measureSpec & MODE_MASK;

  /// `MeasureSpec.getSize(measureSpec)`: the low 30 bits, never negative.
  static int getSize(int measureSpec) => measureSpec & _SIZE_MASK;

  /// The short form of [measureSpec] in the measure-request transcript: the
  /// mode's letter (`E`, `A` or `U`, `?` for any other mode) followed by the
  /// size, such as `E400`, `A800` or `U0`.
  static String toShortString(int measureSpec) {
    final mode = getMode(measureSpec);
    final letter = switch (mode) {
      EXACTLY => 'E',
      AT_MOST => 'A',
      UNSPECIFIED => 'U',
      _ => '?',
    };
    return '$letter${getSize(measureSpec)}';
  }

  /// `ViewGroup.getChildMeasureSpec(spec, padding, childDimension)`: the spec
  /// a parent measured under [spec] gives a child whose layout size is
  /// [childDimension], after taking [padding] from the parent's size.
  ///
  /// [childDimension] is a size (0 or more), `BasicMeasure.MATCH_PARENT`
  /// (-1) or `BasicMeasure.WRAP_CONTENT` (-2). Any other value, or a [spec]
  /// whose mode is none of the three, gives `makeMeasureSpec(0, UNSPECIFIED)`,
  /// as Java's switch leaves it.
  static int getChildMeasureSpec(int spec, int padding, int childDimension) {
    final specMode = getMode(spec);
    final specSize = getSize(spec);
    // Math.max(0, specSize - padding), with Java's 32-bit subtraction.
    final available = (specSize - padding).toSigned(32);
    final size = available > 0 ? available : 0;
    var resultSize = 0;
    var resultMode = UNSPECIFIED;
    switch (specMode) {
      case EXACTLY:
        // The parent has imposed an exact size on us.
        if (childDimension >= 0) {
          resultSize = childDimension;
          resultMode = EXACTLY;
        } else if (childDimension == _LP_MATCH_PARENT) {
          resultSize = size;
          resultMode = EXACTLY;
        } else if (childDimension == _LP_WRAP_CONTENT) {
          resultSize = size;
          resultMode = AT_MOST;
        }
      case AT_MOST:
        // The parent has imposed a maximum size on us.
        if (childDimension >= 0) {
          resultSize = childDimension;
          resultMode = EXACTLY;
        } else if (childDimension == _LP_MATCH_PARENT) {
          resultSize = size;
          resultMode = AT_MOST;
        } else if (childDimension == _LP_WRAP_CONTENT) {
          resultSize = size;
          resultMode = AT_MOST;
        }
      case UNSPECIFIED:
        // The parent asked to see how big we want to be.
        if (childDimension >= 0) {
          resultSize = childDimension;
          resultMode = EXACTLY;
        } else if (childDimension == _LP_MATCH_PARENT) {
          resultSize = USE_ZERO_UNSPECIFIED_MEASURE_SPEC ? 0 : size;
          resultMode = UNSPECIFIED;
        } else if (childDimension == _LP_WRAP_CONTENT) {
          resultSize = USE_ZERO_UNSPECIFIED_MEASURE_SPEC ? 0 : size;
          resultMode = UNSPECIFIED;
        }
    }
    return makeMeasureSpec(resultSize, resultMode);
  }

  /// `View.resolveSizeAndState(size, measureSpec, childMeasuredState)`: the
  /// measured size a view that wants [size] reports under [measureSpec].
  ///
  /// EXACTLY gives the spec's size; AT_MOST gives [size], or the spec's size
  /// with [MEASURED_STATE_TOO_SMALL] when [size] is larger; UNSPECIFIED (and
  /// a corrupted mode) gives [size]. The state bits of [childMeasuredState]
  /// are added. The result is Java's `int` as an unsigned 32-bit value.
  static int resolveSizeAndState(
    int size,
    int measureSpec,
    int childMeasuredState,
  ) {
    final specMode = getMode(measureSpec);
    final specSize = getSize(measureSpec);
    final int result;
    switch (specMode) {
      case AT_MOST:
        if (specSize < size) {
          result = specSize | MEASURED_STATE_TOO_SMALL;
        } else {
          result = size;
        }
      case EXACTLY:
        result = specSize;
      default:
        result = size;
    }
    return (result | (childMeasuredState & MEASURED_STATE_MASK)) & 0xFFFFFFFF;
  }

  /// `ViewGroup.LayoutParams.MATCH_PARENT` (`BasicMeasure.MATCH_PARENT`).
  static const int _LP_MATCH_PARENT = -1;

  /// `ViewGroup.LayoutParams.WRAP_CONTENT` (`BasicMeasure.WRAP_CONTENT`).
  static const int _LP_WRAP_CONTENT = -2;
}
