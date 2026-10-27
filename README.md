# flutter_constraint_layout

Android's ConstraintLayout for Flutter. Every child of one flat
`ConstraintLayout` declares where its own edges go, pinned to the parent or to
a sibling, and how it is sized. Rows inside columns inside stacks become a
single layer of anchored siblings, with chains, guidelines, barriers, bias, and
aspect ratios built in.

Layouts are resolved by a pure-Dart port of `androidx.constraintlayout.core`,
the engine behind Android's ConstraintLayout, run through Android's own
measure passes, so the same layout runs on every Flutter platform with no
native code and gets Android's frames, to the pixel. Checked against
Android's own code, the frames match on 60,000 real widget trees and on more
than 1.8 million engine layouts.

[Documentation](https://constraints.birju.dev/docs) ·
[Live examples](https://constraints.birju.dev) ·
[Package guide](packages/flutter_constraint_layout/README.md)

## Install

```sh
flutter pub add flutter_constraint_layout
```

The package needs Dart 3.12 and Flutter 3.44 or later. Its API is built around
Dart's dot shorthands, so you write `.startOf(parent)` where the full form is
`HorizontalLink.startOf(parent)`.

## Quick start

A profile row: an avatar, a name, and a button, with no `Row`, `Expanded`, or
`Padding`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

class ProfileRow extends StatelessWidget {
  const ProfileRow({super.key});

  @override
  Widget build(BuildContext context) {
    return ConstraintLayout(
      children: [
        Constrained(
          id: #avatar,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          child: const CircleAvatar(child: Icon(Icons.person)),
        ),
        Constrained(
          id: #follow,
          end: .endOf(parent, margin: 16),
          top: .topOf(#avatar),
          bottom: .bottomOf(#avatar),
          child: FilledButton(onPressed: () {}, child: const Text('Follow')),
        ),
        Constrained(
          id: #name,
          start: .endOf(#avatar, margin: 12),
          end: .startOf(#follow, margin: 12),
          top: .topOf(#avatar),
          bottom: .bottomOf(#avatar),
          width: .matchConstraint,
          child: const Text('Ada Lovelace'),
        ),
      ],
    );
  }
}
```

- Each child is wrapped in a `Constrained` with a `Symbol` id. Siblings refer
  to each other by id, and `parent` is the layout itself.
- Read a link as "my edge, at the target's edge":
  `start: .endOf(#avatar, margin: 12)` puts the name's start edge 12 logical
  pixels past the avatar's end edge.
- Two opposing links center a child between them. The button and the name link
  their top and bottom to the avatar's, so both are centered on it vertically.
- `width: .matchConstraint` fills the space between the two horizontal links,
  so the name takes whatever room the avatar and the button leave.
- `start` and `end` follow the text direction, so the row mirrors itself in a
  right-to-left locale.

The layout fills the space it is given on a bounded axis and wraps its children
on an unbounded one, such as the main axis of a scroll view. For a complete app,
see [example/main.dart](packages/flutter_constraint_layout/example/main.dart).

## Beyond the basics

- **Chains**: siblings that link to each other in both directions form a
  chain, laid out as `spread`, `spreadInside`, or `packed`, with per-child
  weights.
- **Guidelines and barriers**: anchor to an invisible line at a fixed offset or
  a percent of the layout, or to whichever edge of a set of widgets sticks out
  furthest.
- **Sizing and bias**: fixed, wrap-content, or match-constraint sizes. A
  match-constraint size can take min and max bounds, wrap its content without
  outgrowing its links, or be a percent of the parent. Aspect ratios derive one
  side from the other, and a bias slides a child between two opposing links.
- **Baselines**: align a child's text baseline with a sibling's, as in
  `baseline: .baselineOf(#title)`.
- **Circular positioning**: place a child at an angle and a radius around
  another.
- **Visibility**: `visible`, `invisible`, or `gone`, with a `goneMargin` for
  links to a gone sibling, and `ConstraintGroup` to set it for several
  children at once.
- **Virtual layouts**: `ConstraintFlow` and `ConstraintGrid` arrange children
  that stay direct siblings, so other constraints can still target them.
- **Debug overlay**: in debug builds, `debugShowChains` and
  `debugShowBlueprint` draw the constraints the way Android Studio's layout
  editor does.

The [documentation](https://constraints.birju.dev/docs) shows each layout
feature with a live example, and the
[package guide](packages/flutter_constraint_layout/README.md) covers the full
API.

## Packages

| Package | Path | pub.dev | What it is |
| --- | --- | --- | --- |
| `flutter_constraint_layout` | [packages/flutter_constraint_layout](packages/flutter_constraint_layout) | [flutter_constraint_layout](https://pub.dev/packages/flutter_constraint_layout) | The Flutter widgets: `ConstraintLayout`, `Constrained`, `Guideline`, `Barrier`, `ConstraintFlow`, `ConstraintGrid`, `ConstraintGroup`, and the debug overlay. Start here. |
| `constraint_engine` | [packages/constraint_engine](packages/constraint_engine) | [constraint_engine](https://pub.dev/packages/constraint_engine) | The layout engine: a line-faithful, pure-Dart port of `androidx.constraintlayout.core` and of the measure of Android's `ConstraintLayout` view, with Android's measure passes, `Direct` pass, and Cassowary solver in Android's 32-bit float arithmetic. No Flutter dependency. |
| `flutter_constraint_layout_lints` | [packages/flutter_constraint_layout_lints](packages/flutter_constraint_layout_lints) | [flutter_constraint_layout_lints](https://pub.dev/packages/flutter_constraint_layout_lints) | An analyzer plugin that warns about duplicate and undefined constraint ids while you edit. |
| `flutter_constraint_layout_website` | [website](website) | Not published | The documentation site, [constraints.birju.dev](https://constraints.birju.dev). |
| `site_kit` | [template](template) | Not published | The site's theme and component kit, used by path or git, with a [storyboard](template/storyboard) app that showcases it. |

## Links

- Documentation: [constraints.birju.dev/docs](https://constraints.birju.dev/docs)
- The documentation as a single Markdown file, for reading offline or giving to
  an AI assistant: [docs.md](https://constraints.birju.dev/docs.md), with a
  summary in [llms.txt](https://constraints.birju.dev/llms.txt)
- Questions, bug reports, and feature requests:
  [GitHub issues](https://github.com/BirjuVachhani/flutter_constraint_layout/issues)

## Contributing

Contributions are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers the
workspace layout, analyzing and testing each package, goldens and coverage, the
CI jobs, the website, and releasing.

## License

BSD 3-Clause; see [LICENSE](LICENSE). Two packages also carry an Apache-2.0
notice for code derived from Android Open Source Project sources:
`constraint_engine`, a port of androidx.constraintlayout core, and the debug
overlay's painter and palette in `flutter_constraint_layout`, adapted from the
rendering of Android Studio's layout editor. Those files carry the Android Open
Source Project copyright line next to ours and are tagged
`SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause`, and the LICENSE files of
[constraint_engine](packages/constraint_engine/LICENSE) and
[flutter_constraint_layout](packages/flutter_constraint_layout/LICENSE) include
the Apache-2.0 text.
