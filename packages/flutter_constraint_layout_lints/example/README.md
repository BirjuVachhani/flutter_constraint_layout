# Example

Enable the plugin in the `analysis_options.yaml` at the root of your package or
workspace, then restart the Dart Analysis Server:

```yaml
plugins:
  flutter_constraint_layout_lints: ^1.0.0
```

With the plugin on, this layout gets two warnings: the second child reuses the
id `#title`, and the third links to `#titel`, which no child defines.

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Widget card() => ConstraintLayout(
      children: [
        Constrained(
          id: #title,
          top: .topOf(parent, margin: 16),
          child: const Text('Title'),
        ),
        Constrained(
          id: #title, // duplicate_constraint_id
          top: .bottomOf(#title, margin: 8),
          child: const Text('Subtitle'),
        ),
        Constrained(
          id: #body,
          top: .bottomOf(#titel, margin: 8), // undefined_constraint_id
          child: const Text('Body'),
        ),
      ],
    );
```

`dart analyze` reports:

```text
warning - lib/card.dart:12:15 - The id 'title' is already used by another child of this ConstraintLayout. Try giving this child an id that is unique within the layout. - duplicate_constraint_id
warning - lib/card.dart:18:26 - The id 'titel' is not defined by any child of this ConstraintLayout. Try correcting the id, or giving a child of this layout that id. - undefined_constraint_id
```

The same warnings appear in your IDE as you type. `flutter analyze` does not
run analyzer plugins, so use `dart analyze` to enforce the rules in CI.
