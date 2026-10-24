import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../constraint_layout_ast.dart';

/// Reports a link, or a helper's `referenced` entry, that names an id no child
/// of the same `ConstraintLayout` defines.
///
/// Ids are scoped to one layout. A link at an id nothing defines cannot be
/// resolved, so the edge it was supposed to anchor is left unconstrained and the
/// child drifts to the layout's origin instead: the usual cause is a typo or an
/// id that was renamed on its child but not at its use sites.
///
/// Unlike a duplicate id, this needs the *complete* set of ids to be visible to
/// say anything. Whenever a child could contribute an id the analyzer cannot
/// see (a widget passed in through a variable or a helper method, a `for`
/// element, a spread of a non-literal list, an id built at runtime), the whole
/// layout is skipped rather than guessed at.
class UndefinedConstraintId extends AnalysisRule {
  static const LintCode code = LintCode(
    'undefined_constraint_id',
    "The id '{0}' is not defined by any child of this ConstraintLayout.",
    correctionMessage:
        'Try correcting the id, or giving a child of this layout that id.',
    severity: DiagnosticSeverity.WARNING,
  );

  UndefinedConstraintId()
    : super(
        name: 'undefined_constraint_id',
        description:
            'Links may only target the reserved id `parent` or an id defined by '
            'a child of the same ConstraintLayout. An unresolved target leaves '
            'the edge unconstrained at runtime.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    var visitor = _Visitor(this);
    registry.addInstanceCreationExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!isConstraintLayoutCreation(node)) return;

    var children = namedArgument(node.argumentList, 'children');
    // A children list built elsewhere hides every id it holds.
    if (children is! ListLiteral) return;

    var scan = _LayoutScan();
    children.accept(_Walker(scan));
    if (!scan.complete) return;

    for (var reference in scan.references) {
      if (!scan.defined.contains(reference.id)) {
        rule.reportAtNode(reference.node, arguments: [reference.id]);
      }
    }
  }
}

/// An id named by a link or by a helper's `referenced` list.
class _Reference {
  _Reference(this.id, this.node);

  final String id;
  final Expression node;
}

/// What one layout's children say about ids: which ones exist, which ones are
/// pointed at, and whether the picture is complete enough to judge.
class _LayoutScan {
  final defined = <String>{};
  final references = <_Reference>[];

  /// Whether every child was visible to the walk. Once this is false the scan
  /// cannot prove an id is missing, so nothing is reported.
  var complete = true;
}

/// Walks one layout's `children` list, collecting the ids it defines and the
/// ids it points at.
///
/// Descends through non-package widgets, since a `Constrained` can sit under a
/// builder-style wrapper and still belong to this layout, and stops at a nested
/// `ConstraintLayout`, whose children live in their own id scope.
class _Walker extends UnifyingAstVisitor<void> {
  _Walker(this.scan);

  final _LayoutScan scan;

  @override
  void visitNode(AstNode node) {
    if (_handle(node)) node.visitChildren(this);
  }

  /// Records what [node] contributes, returning whether to descend into it.
  bool _handle(AstNode node) {
    switch (node) {
      case InstanceCreationExpression():
        if (isConstraintLayoutCreation(node)) return false;
        if (isPackageWidgetCreation(node)) _collectFrom(node.argumentList);
        return true;
      // Each iteration builds a child from the same expression, so the ids the
      // loop produces (and how many) are not knowable here.
      case ForElement():
        scan.complete = false;
        return false;
      // The identifier inside a constructor name is not a value, so there is
      // nothing to collect or to be cautious about in there.
      case ConstructorName():
        return false;
      case SpreadElement(:var expression):
        if (expression is! ListLiteral) {
          scan.complete = false;
          return false;
        }
        return true;
      // Both branches of an `if` are treated as present: an id defined in
      // either one is a real id of this layout, and pointing at it is not by
      // itself a mistake.
      case Expression():
        if (_isOpaqueWidget(node)) {
          scan.complete = false;
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  /// Whether [expression] yields a widget the walk cannot look inside, and so
  /// could be hiding a child with an id.
  bool _isOpaqueWidget(Expression expression) {
    if (!couldBeWidget(expression.staticType)) return false;
    return switch (expression) {
      InstanceCreationExpression() ||
      DotShorthandConstructorInvocation() ||
      DotShorthandInvocation() ||
      ParenthesizedExpression() => false,
      _ => true,
    };
  }

  /// Reads the `id`, link, and `referenced` arguments of one package widget.
  void _collectFrom(ArgumentList arguments) {
    var idExpression = namedArgument(arguments, 'id');
    if (idExpression != null) {
      var id = symbolName(idExpression);
      if (id == null) {
        // An id computed at runtime could be anything, including the one a
        // link is looking for.
        scan.complete = false;
        return;
      }
      scan.defined.add(id);
    }

    for (var parameter in linkParameters) {
      var link = namedArgument(arguments, parameter);
      if (link == null) continue;
      var argumentList = argumentListOf(link);
      if (argumentList == null) continue;
      var target = firstPositionalArgument(argumentList);
      if (target != null) _addReference(target);
    }

    var referenced = namedArgument(arguments, referencedParameter);
    if (referenced is ListLiteral) {
      for (var element in referenced.elements) {
        if (element is Expression) _addReference(element);
      }
    }
  }

  void _addReference(Expression target) {
    var id = symbolName(target);
    // An unresolvable target is simply not checked; unlike a missing
    // definition, it cannot cause a false report.
    if (id == null || id == parentId) return;
    scan.references.add(_Reference(id, target));
  }
}
