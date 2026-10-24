import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:flutter_constraint_layout_lints/src/rules/undefined_constraint_id.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UndefinedConstraintIdTest);
  });
}

@reflectiveTest
class UndefinedConstraintIdTest extends AnalysisRuleTest {
  // The rule reasons about what could be hiding a widget, so the mock Flutter
  // package has to be resolvable.
  @override
  bool get addFlutterPackageDep => true;

  @override
  void setUp() {
    rule = UndefinedConstraintId();
    // A stand-in for the real package: the class and parameter names and the
    // library URI are what the rule reads, so the bodies are left out.
    newPackage('flutter_constraint_layout').addFile('lib/flutter_constraint_layout.dart', r'''
import 'package:flutter/widgets.dart';

const Symbol parent = #parent;

class ConstraintLayout extends StatelessWidget {
  const ConstraintLayout({super.key, this.children});
  final List<Widget>? children;
}

class Constrained extends StatelessWidget {
  const Constrained({
    required this.id,
    this.child,
    this.left,
    this.right,
    this.start,
    this.end,
    this.top,
    this.bottom,
    this.baseline,
    this.circle,
  });
  final Symbol id;
  final Widget? child;
  final HorizontalLink? left;
  final HorizontalLink? right;
  final HorizontalLink? start;
  final HorizontalLink? end;
  final VerticalLink? top;
  final VerticalLink? bottom;
  final VerticalLink? baseline;
  final CircularLink? circle;
}

class Guideline extends StatelessWidget {
  const Guideline({required this.id});
  final Symbol id;
}

class Barrier extends StatelessWidget {
  const Barrier({required this.id, required this.referenced});
  final Symbol id;
  final List<Symbol> referenced;
}

class HorizontalLink {
  const HorizontalLink.startOf(this.target, {this.margin = 0});
  const HorizontalLink.endOf(this.target, {this.margin = 0});
  const HorizontalLink.leftOf(this.target, {this.margin = 0});
  const HorizontalLink.rightOf(this.target, {this.margin = 0});
  final Symbol target;
  final double margin;
}

class VerticalLink {
  const VerticalLink.topOf(this.target, {this.margin = 0});
  const VerticalLink.bottomOf(this.target, {this.margin = 0});
  const VerticalLink.baselineOf(this.target, {this.margin = 0});
  final Symbol target;
  final double margin;
}

class CircularLink {
  const CircularLink.around(this.target, {this.angle = 0, this.radius = 0});
  final Symbol target;
  final double angle;
  final double radius;
}
''');
    super.setUp();
  }

  Future<void> test_barrierReferenced_undefined() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Constrained(id: #a, child: Text('a')),
    Barrier(id: #edge, referenced: [#a, #b]),
  ],
);
''',
      [lint(244, 2)],
    );
  }

  Future<void> test_circleTarget_undefined() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Constrained(
      id: #dot,
      circle: CircularLink.around(#hub, radius: 96),
      child: Text('dot'),
    ),
  ],
);
''',
      [lint(228, 4)],
    );
  }

  Future<void> test_constIdentifierTarget_undefined() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

const titleId = #title;

Widget f() => ConstraintLayout(
  children: [
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(titleId),
      child: Text('body'),
    ),
  ],
);
''',
      [lint(253, 7)],
    );
  }

  Future<void> test_definedById_inIfBranch() async {
    // The id does exist in the source; whether the branch is taken is a
    // runtime question this rule does not try to answer.
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f(bool compact) => ConstraintLayout(
  children: [
    if (compact) Constrained(id: #title, child: Text('t')),
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(#title),
      child: Text('body'),
    ),
  ],
);
''');
  }

  Future<void> test_definedByGuideline() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Guideline(id: #gutter),
    Constrained(
      id: #body,
      start: HorizontalLink.endOf(#gutter),
      child: Text('body'),
    ),
  ],
);
''');
  }

  Future<void> test_definedUnderBuilder() async {
    // `Constrained` can sit under a builder-style wrapper and still be a child
    // of this layout, so the id it declares counts as defined.
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Builder(builder: (context) => Constrained(id: #title, child: Text('t'))),
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(#title),
      child: Text('body'),
    ),
  ],
);
''');
  }

  Future<void> test_dotShorthandTarget_undefined() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Constrained(id: #body, top: .topOf(#title), child: Text('body')),
  ],
);
''',
      [lint(200, 6)],
    );
  }

  Future<void> test_incomplete_forElement() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f(List<String> labels) => ConstraintLayout(
  children: [
    for (var label in labels) Constrained(id: #row, child: Text(label)),
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(#title),
      child: Text('body'),
    ),
  ],
);
''');
  }

  Future<void> test_incomplete_opaqueChildWidget() async {
    // `extra` could be anything, including a `Constrained` declaring #title.
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f(Widget extra) => ConstraintLayout(
  children: [
    Constrained(id: #body, top: VerticalLink.bottomOf(#title), child: extra),
  ],
);
''');
  }

  Future<void> test_incomplete_opaqueListElement() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget header() => Constrained(id: #title, child: Text('t'));

Widget f() => ConstraintLayout(
  children: [
    header(),
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(#title),
      child: Text('body'),
    ),
  ],
);
''');
  }

  Future<void> test_incomplete_runtimeId() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f(String name) => ConstraintLayout(
  children: [
    Constrained(id: Symbol(name), child: Text('a')),
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(#title),
      child: Text('body'),
    ),
  ],
);
''');
  }

  Future<void> test_incomplete_spreadOfNonLiteral() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f(List<Widget> extras) => ConstraintLayout(
  children: [
    ...extras,
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(#title),
      child: Text('body'),
    ),
  ],
);
''');
  }

  Future<void> test_nestedLayout_referencesOuterId() async {
    // Ids do not cross a layout boundary, so #outer is unresolvable inside.
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Constrained(
      id: #outer,
      child: ConstraintLayout(
        children: [
          Constrained(
            id: #inner,
            top: VerticalLink.topOf(#outer),
            child: Text('i'),
          ),
        ],
      ),
    ),
  ],
);
''',
      [lint(330, 6)],
    );
  }

  Future<void> test_parentTarget() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Constrained(
      id: #body,
      top: VerticalLink.topOf(parent),
      start: HorizontalLink.startOf(parent),
      child: Text('body'),
    ),
  ],
);
''');
  }

  Future<void> test_undefinedTarget() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Constrained(id: #title, child: Text('title')),
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(#titel),
      child: Text('body'),
    ),
  ],
);
''',
      [lint(279, 6)],
    );
  }

  Future<void> test_undefinedTarget_reportsEachSite() async {
    await assertDiagnostics(
      r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(#title),
      start: HorizontalLink.startOf(#title),
      child: Text('body'),
    ),
  ],
);
''',
      [lint(228, 6), lint(273, 6)],
    );
  }

  Future<void> test_wellFormedLayout() async {
    await assertNoDiagnostics(r'''
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';

Widget f() => ConstraintLayout(
  children: [
    Constrained(
      id: #title,
      top: VerticalLink.topOf(parent),
      child: Text('title'),
    ),
    Constrained(
      id: #body,
      top: VerticalLink.bottomOf(#title, margin: 8),
      start: HorizontalLink.startOf(#title),
      child: Text('body'),
    ),
  ],
);
''');
  }
}
