import 'package:flutter/material.dart';
import 'package:shiki_flutter/shiki_flutter.dart';

/// Owns the single, shared [ShikiHighlighter] the whole site highlights with,
/// plus the language registry `CodeBlock` resolves string ids against.
///
/// Configured once from `SiteKit.init()`; nothing else needs to touch it.
/// Tokenization runs off the UI thread (see `SiteKit.init`) and the
/// highlighter's own token cache keeps rebuilds instant, so there is no
/// hand-rolled span cache here.
class SiteHighlighter {
  SiteHighlighter._(this.theme, List<CodeLanguage> languages)
    : _languagesById = {for (final lang in languages) lang.id: lang},
      _languages = List.unmodifiable(languages);

  /// The languages a site gets without asking. These grammars are referenced
  /// from this default, so they are always in the bundle even when
  /// `SiteKit.init(languages: ...)` overrides them; the four together are
  /// small, and a docs site normally wants all of them.
  static List<CodeLanguage> get defaultLanguages => [
    CodeLanguages.dart,
    CodeLanguages.yaml,
    CodeLanguages.shellscript,
    CodeLanguages.json,
  ];

  /// The stock code theme: the Pierre light/dark pair, whose hues the
  /// [BrandPalette] is sampled from, so code and illustrations agree.
  static const ShikiThemeBase defaultTheme = ShikiDualTheme(
    light: PierreThemes.pierreLight,
    dark: PierreThemes.pierreDark,
  );

  static SiteHighlighter? _instance;

  /// The shared service, built with the stock theme and languages if
  /// [configure] was never called.
  static SiteHighlighter get instance =>
      _instance ??= SiteHighlighter._(defaultTheme, defaultLanguages);

  /// Replaces the shared service. Called by `SiteKit.init()`; calling it again
  /// later rebuilds the highlighter, dropping the token cache with it.
  static void configure({
    ShikiThemeBase? theme,
    List<CodeLanguage>? languages,
  }) {
    _instance = SiteHighlighter._(
      theme ?? defaultTheme,
      languages ?? defaultLanguages,
    );
  }

  /// The theme (or light/dark pair) code blocks default to.
  final ShikiThemeBase theme;

  final Map<String, CodeLanguage> _languagesById;
  final List<CodeLanguage> _languages;

  /// Every registered language, in registration order.
  List<CodeLanguage> get languages => _languages;

  late final ShikiHighlighter _highlighter = ShikiHighlighter()
    ..preload(langs: _languages, themes: _themesToPreload());

  /// The shared highlighter, e.g. to pass straight to a [ShikiCodeView].
  ShikiHighlighter get highlighter => _highlighter;

  /// The registered language for [id] (e.g. `'dart'`), or null when the id is
  /// not registered. `CodeBlock` renders unhighlighted mono text for null,
  /// rather than failing on a typo or an unexpected fenced language.
  CodeLanguage? languageFor(String id) => _languagesById[id.toLowerCase()];

  /// Whether [id] resolves to a registered grammar.
  bool supportsLanguage(String id) => _languagesById.containsKey(id);

  final Map<String, Color> _backgrounds = {};

  /// The background color declared by the theme registered as [themeId],
  /// falling back to [fallback] when the theme declares none.
  Color backgroundOf(String themeId, Color fallback) {
    return _backgrounds.putIfAbsent(themeId, () {
      final registration = _highlighter.getThemeRegistration(themeId);
      return parseColor(registration.bg) ?? fallback;
    });
  }

  /// The background the default code theme paints for [isDark]. Shared by code
  /// cards and any pane meant to sit on the same surface.
  Color defaultBackground({required bool isDark, required Color fallback}) =>
      backgroundOf(theme.resolve(isDark: isDark).id, fallback);

  /// Both halves of a dual theme, or the single theme, so preloading warms
  /// whichever brightness the visitor lands in. Resolving both and
  /// de-duplicating covers a plain theme and any custom [ShikiThemeBase] with
  /// one code path.
  List<ShikiTheme> _themesToPreload() => {
    theme.resolve(isDark: false),
    theme.resolve(isDark: true),
  }.toList();
}
