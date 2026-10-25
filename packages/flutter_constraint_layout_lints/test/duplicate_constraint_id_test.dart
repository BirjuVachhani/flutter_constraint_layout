import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:flutter_constraint_layout_lints/src/rules/duplicate_constraint_id.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DuplicateConstraintIdTest);
  });
}

@reflectiveTest
class DuplicateConstraintIdTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = DuplicateConstraintId();
    // A stand-in for the real package: only the class names, the library URI,
    // and the parameter names matter to the rule, so bodies and the Flutter
    // widget hierarchy are left out.
    newPackage('flutter_constraint_layout').addFile('lib/flutter_constraint_layout.dart', r'''
class ConstraintLayout {
  const ConstraintLayout({this.children});
  final List<Object>? children;
}

class Constrained {
  const Constrained({required this.id, this.child});
  final Symbol id;
  final Object? child;
}

class Guideline {
  const Guideline({required this.id});
  final Symbol id;
}

class ConstraintGroup {
  const ConstraintGroup({required this.id, required this.referenced});
  final Symbol id;
  final List<Symbol> referenced;
}
''');
    super.setUp();
  }

  Future<void> test_conditionalBranches_sameIdInEachBranch() async {
    // Mutually exclusive, so only one of the two is ever built.
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f(bool compact) => ConstraintLayout(
  children: [
    if (compact)
      Constrained(id: #body, child: 'compact')
    else
      Constrained(id: #body, child: 'full'),
  ],
);
''');
  }

  Future<void> test_constIdentifierId_duplicate() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

const headerId = #header;

Object f() => ConstraintLayout(
  children: [
    Constrained(id: headerId, child: 'a'),
    Constrained(id: #header, child: 'b'),
  ],
);
''',
      [lint(212, 7)],
    );
  }

  Future<void> test_duplicateId() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f() => ConstraintLayout(
  children: [
    Constrained(id: #header, child: 'a'),
    Constrained(id: #header, child: 'b'),
  ],
);
''',
      [lint(184, 7)],
    );
  }

  Future<void> test_duplicateId_acrossWidgetTypes() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f() => ConstraintLayout(
  children: [
    Guideline(id: #gutter),
    Constrained(id: #gutter, child: 'a'),
  ],
);
''',
      [lint(170, 7)],
    );
  }

  Future<void> test_duplicateId_groupAndChild() async {
    // A group's id is an id of the layout like any other, even though a group
    // takes no part in the layout itself.
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f() => ConstraintLayout(
  children: [
    Constrained(id: #details, child: 'a'),
    ConstraintGroup(id: #details, referenced: [#details]),
  ],
);
''',
      [lint(189, 8)],
    );
  }

  Future<void> test_duplicateId_twoGroups() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f() => ConstraintLayout(
  children: [
    Constrained(id: #a, child: 'a'),
    ConstraintGroup(id: #toggle, referenced: [#a]),
    ConstraintGroup(id: #toggle, referenced: [#a]),
  ],
);
''',
      [lint(235, 7)],
    );
  }

  Future<void> test_duplicateId_reportsEachRepeat() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f() => ConstraintLayout(
  children: [
    Constrained(id: #a, child: '1'),
    Constrained(id: #a, child: '2'),
    Constrained(id: #a, child: '3'),
  ],
);
''',
      [lint(179, 2), lint(216, 2)],
    );
  }

  Future<void> test_duplicateId_withContextMessage() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f() => ConstraintLayout(
  children: [
    Constrained(id: #header, child: 'a'),
    Constrained(id: #header, child: 'b'),
  ],
);
''',
      [
        lint(
          184,
          7,
          contextMessages: [
            contextMessage(
              testFile,
              142,
              7,
              textContains: ["The id 'header' is already used here."],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> test_idOnUnrelatedWidget() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

class Other {
  const Other({required this.id});
  final Symbol id;
}

Object f() => ConstraintLayout(
  children: [
    Other(id: #a),
    Other(id: #a),
  ],
);
''');
  }

  Future<void> test_nestedLayouts_sameIdInEach() async {
    // Ids only have to be unique within one layout.
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f() => ConstraintLayout(
  children: [
    Constrained(
      id: #box,
      child: ConstraintLayout(
        children: [
          Constrained(id: #box, child: 'inner'),
        ],
      ),
    ),
  ],
);
''');
  }

  Future<void> test_opaqueChildren() async {
    // The children list is built elsewhere, so there is nothing to compare.
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

List<Object> children() => [
  Constrained(id: #a, child: '1'),
  Constrained(id: #a, child: '2'),
];

Object f() => ConstraintLayout(children: children());
''');
  }

  Future<void> test_spreadListLiteral_duplicate() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f() => ConstraintLayout(
  children: [
    Constrained(id: #a, child: '1'),
    ...[
      Constrained(id: #a, child: '2'),
    ],
  ],
);
''',
      [lint(190, 2)],
    );
  }

  Future<void> test_uniqueIds() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

Object f() => ConstraintLayout(
  children: [
    Constrained(id: #header, child: 'a'),
    Constrained(id: #body, child: 'b'),
  ],
);
''');
  }
}
