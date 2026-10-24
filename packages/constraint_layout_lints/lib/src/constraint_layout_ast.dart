/// AST helpers shared by the rules in this plugin.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// The library that owns `ConstraintLayout` and every id-bearing child widget.
///
/// Gating on this URI keeps the rules from firing on unrelated classes that
/// happen to be named `ConstraintLayout` or to take an `id`.
const packageUriPrefix = 'package:constraint_layout/';

/// The reserved id standing for the layout itself, declared by the package as
/// `const Symbol parent = #parent`. It is never defined by a child.
const parentId = 'parent';

/// The `Constrained` parameters whose value is a link at another child.
///
/// Each takes the target id as its first positional argument, as in
/// `top: .topOf(#header, margin: 8)`.
const linkParameters = {
  'left',
  'right',
  'start',
  'end',
  'top',
  'bottom',
  'baseline',
  'circle',
};

/// The parameter through which `Barrier`, `ConstraintFlow`, and `ConstraintGrid`
/// name the children they act on.
const referencedParameter = 'referenced';

/// Whether [element] is declared by the `constraint_layout` package.
bool isFromPackage(Element? element) {
  var uri = element?.library?.uri.toString();
  return uri != null && uri.startsWith(packageUriPrefix);
}

/// Whether [node] creates a `ConstraintLayout` from this package.
bool isConstraintLayoutCreation(InstanceCreationExpression node) {
  var element = node.constructorName.type.element;
  return element is ClassElement &&
      element.name == 'ConstraintLayout' &&
      isFromPackage(element);
}

/// Whether [node] creates a widget of this package, such as `Constrained`.
bool isPackageWidgetCreation(InstanceCreationExpression node) =>
    isFromPackage(node.constructorName.type.element);

/// The value passed to the [name] parameter, or `null` if it is not passed.
Expression? namedArgument(ArgumentList arguments, String name) {
  for (var argument in arguments.arguments) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument.argumentExpression;
    }
  }
  return null;
}

/// The first positional argument in [arguments], or `null` if there is none.
///
/// Positional arguments are the entries that are plain expressions; named ones
/// are [NamedArgument]s.
Expression? firstPositionalArgument(ArgumentList arguments) {
  for (var argument in arguments.arguments) {
    if (argument is Expression) return argument;
  }
  return null;
}

/// The argument list of [expression] if it is a call of any form, covering
/// dot shorthands (`.topOf(#a)`) alongside named constructors and functions.
ArgumentList? argumentListOf(Expression expression) => switch (expression) {
  InstanceCreationExpression() => expression.argumentList,
  InvocationExpression() => expression.argumentList,
  _ => null,
};

/// The `Symbol` an id or link target resolves to, without the leading `#`, or
/// `null` if it cannot be resolved statically.
///
/// Handles the literal form (`#header`) and a reference to a constant, such as
/// `const headerId = #header` or a `static const` field.
String? symbolName(Expression expression) {
  if (expression is SymbolLiteral) {
    return expression.components.map((token) => token.lexeme).join('.');
  }
  if (expression is Identifier) {
    var element = expression.element;
    // Reading a top-level variable or a field resolves to its (synthetic)
    // getter, so step back to the variable that induced it. A local const is
    // already a variable.
    if (element is GetterElement) {
      element = element.variable;
    }
    if (element is VariableElement) {
      return element.computeConstantValue()?.toSymbolValue();
    }
  }
  return null;
}

/// Whether a value of [type] could be a Flutter widget, and so could hide an
/// id-bearing child of the layout somewhere inside it.
///
/// A `dynamic` or invalid type counts as "could be", so that callers stay on the
/// cautious side. A *missing* type does not: an expression with no static type
/// is one the analyzer never treated as a value, such as the identifier inside a
/// constructor name.
bool couldBeWidget(DartType? type) {
  if (type == null) return false;
  if (type is DynamicType || type is InvalidType) return true;
  if (type is! InterfaceType) return false;
  if (type.isDartCoreObject) return true;
  for (var candidate in [type, ...type.allSupertypes]) {
    var element = candidate.element;
    if (element.name == 'Widget' &&
        (element.library.uri.toString().startsWith('package:flutter/'))) {
      return true;
    }
  }
  return false;
}
