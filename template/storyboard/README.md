# site_kit storyboard

An interactive canvas of every `site_kit` design token, component, and page
pattern, rendered live in light and dark.

```bash
flutter run -d chrome
```

## The canvas

Frames are laid out in columns, one per group, reading left to right from
foundations through components to whole pages.

| Gesture | Action |
| --- | --- |
| Drag | Pan |
| Scroll or pinch | Zoom |
| Click a rail entry | Fly to that frame and highlight it |
| Click a frame | Focus it |
| `⌘ +` / `⌘ −` | Zoom in and out around the center |
| `⌘ 0` | Back to 100% |
| `⌘ 1` | Fit everything |

Use <kbd>Ctrl</kbd> in place of <kbd>⌘</kbd> off macOS.

The toolbar carries the zoom controls, the dot-grid toggle, and a System /
Light / Dark switch. Flipping the theme repaints every frame at once, which is
the fastest way to check a palette change in both modes.

## Deep links

Every frame has a URL:

- `/?frame=<id>` opens the canvas already flown to that frame.
- `/frame/<id>` opens the frame on its own page.

The id is the mono chip beside each frame's title. This is the same path-based
routing the package gives a real site, so a refresh or a shared link lands
exactly where it should.

## Page patterns

The last group renders complete pages inside `ViewportFrame`, which overrides
the `MediaQuery` size for its subtree. The same widget tree appears at 1160px
and 390px side by side, genuinely laid out for those widths, so responsive
behavior is visible rather than described. Scroll inside a frame to move that
page, not the canvas.

## Adding a frame

Specimens are plain data. Add one to the right group in
`lib/src/catalog/foundations.dart`, `components.dart`, or `patterns.dart`:

```dart
Specimen(
  id: 'my-thing',
  title: 'MyThing',
  description: 'One line on what this shows or why it exists.',
  width: 420,
  builder: (context) => const MyThing(),
),
```

The rail, the search box, the smoke test, and `/frame/my-thing` all pick it up
from there. `surface: SpecimenSurface.page` puts the demo on the page
background instead of a card (right for nav bars, footers, and heroes), and
`padded: false` lets it run edge to edge.

Keep ids stable: they are URLs.

## Tests

```bash
flutter test
```

`test/storyboard_test.dart` builds every specimen on its own, so a failure
names the frame that broke, then boots the whole app once. Add a frame and it
is covered automatically.
