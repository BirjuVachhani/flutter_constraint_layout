import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/error.dart';
// DiagnosticMessage has no public implementation, and context messages are the
// only way to point at the first use of the id from the second one.
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart'
    show DiagnosticMessageImpl;

import '../constraint_layout_ast.dart';

/// Reports a second child of the same `ConstraintLayout` that reuses an id.
///
/// Ids must be unique within a layout: the engine keys every child by its id,
/// so a duplicate silently shadows the earlier child and any link pointing at
/// that id resolves to whichever one the engine indexed last.
class DuplicateConstraintId extends AnalysisRule {
  static const LintCode code = LintCode(
    'duplicate_constraint_id',
    "The id '{0}' is already used by another child of this ConstraintLayout.",
    correctionMessage:
        'Try giving this child an id that is unique within the '
        'layout.',
    severity: DiagnosticSeverity.WARNING,
  );

  DuplicateConstraintId()
    : super(
        name: 'duplicate_constraint_id',
        description:
            'Children of a ConstraintLayout must have unique ids. A duplicate '
            'id shadows the earlier child, and links that target the id '
            'resolve to only one of them.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    var visitor = _Visitor(this, context);
    registry.addInstanceCreationExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!isConstraintLayoutCreation(node)) return;

    var children = namedArgument(node.argumentList, 'children');
    // Anything other than an inline list (a variable, a method call) is opaque
    // to static analysis, so there is nothing to compare.
    if (children is! ListLiteral) return;

    _collect(children.elements, <String, Expression>{});
  }

  /// Walks the direct children of one layout, reporting ids already in [seen].
  ///
  /// [seen] maps an id name to the expression that first introduced it.
  void _collect(
    List<CollectionElement> elements,
    Map<String, Expression> seen,
  ) {
    for (var element in elements) {
      switch (element) {
        case SpreadElement(:var expression):
          // `...[a, b]` is still a statically known set of children. A spread
          // of anything else is opaque.
          if (expression is ListLiteral) {
            _collect(expression.elements, seen);
          }
        case IfElement(:var thenElement, :var elseElement):
          // Branches are mutually exclusive, so ids may legitimately repeat
          // across them. Each branch gets its own copy of [seen] and its ids
          // are not merged back: a duplicate inside a branch is still caught,
          // while a clash that depends on the condition is left alone.
          _collect([thenElement], Map.of(seen));
          if (elseElement != null) {
            _collect([elseElement], Map.of(seen));
          }
        // A `for` element contributes one child per iteration, all built from
        // the same expression, so there is no static duplicate to find.
        case ForElement():
          break;
        case Expression():
          _check(element, seen);
        default:
          break;
      }
    }
  }

  void _check(Expression child, Map<String, Expression> seen) {
    if (child is! InstanceCreationExpression) return;
    if (!isPackageWidgetCreation(child)) return;

    var idExpression = namedArgument(child.argumentList, 'id');
    if (idExpression == null) return;
    var id = symbolName(idExpression);
    if (id == null) return;

    var previous = seen[id];
    if (previous == null) {
      seen[id] = idExpression;
      return;
    }

    rule.reportAtNode(
      idExpression,
      arguments: [id],
      contextMessages: [_contextMessage(previous, id)],
    );
  }

  DiagnosticMessage _contextMessage(Expression previous, String id) {
    return DiagnosticMessageImpl(
      filePath: context.currentUnit!.file.path,
      offset: previous.offset,
      length: previous.length,
      message: "The id '$id' is already used here.",
      url: null,
    );
  }
}
