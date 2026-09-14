# Root Platform Locale Directionality

## Problem

After the first accepted presentation, `BonsaiFlutterRoot` creates the only
`MaterialApp` around `EnvironmentReporter` and `BonsaiFlutterView`. It does not
set `supportedLocales`, `localizationsDelegates`, or a locale resolution
callback. Flutter therefore uses `MaterialApp`'s default supported locale list,
which contains only `en-US`, together with English-only default Material,
Cupertino, and Widgets localization delegates.

When the platform locale changes to `ar-SA`, the application resolves back to
English. The default Widgets localization also hard-codes
`TextDirection.ltr`. `EnvironmentReporter` is inside that application and
prefers `Localizations.maybeLocaleOf(context)` over
`PlatformDispatcher.instance.locale`, so it reports the resolved English
locale rather than the platform locale. Native widgets and OCaml consequently
agree on the wrong LTR environment.

This affects every RTL application below `BonsaiFlutterRoot`, not just the
expandable composer. Large text and other `MediaQuery` environment updates work
because they do not depend on Material locale resolution.

Flutter's installed `flutter_localizations` package provides the relevant
global delegates. `GlobalWidgetsLocalizations` maps Arabic, Farsi, Hebrew,
Pashto, Sindhi, and Urdu to RTL, while `GlobalMaterialLocalizations.delegates`
also installs localized Material and Cupertino resources. The
`bonsai_flutter` package does not currently depend on `flutter_localizations`.

## Evidence

- The internal `MaterialApp` previously omitted `supportedLocales`,
  `localizationsDelegates`, and a locale-list resolution callback.
- A RED root test could not import `flutter_localizations`; before the fix the
  root resolved an Arabic platform preference through the default English-only
  application configuration.
- `EnvironmentReporter` already preferred the surrounding `Localizations`
  locale, so placing it below one corrected application boundary required no
  environment payload or OCaml API change.

## Proposal

Specify one framework-owned effective-locale contract for the root's internal
`MaterialApp`:

- support every language covered by `GlobalMaterialLocalizations` and select
  the first platform-preferred locale supported by the installed global
  Flutter localization delegates, preserving its language, script, and country
  subtags whenever its language is supported, even when the generated resource
  resolves through a language-level fallback;
- fall back deterministically to English for an unsupported platform locale;
- use global Material, Cupertino, and Widgets delegates so the same resolved
  locale supplies native strings and `WidgetsLocalizations.textDirection`;
- let `MaterialApp`'s resulting `Localizations` and `Directionality` wrap
  `EnvironmentReporter`, so its existing context-first lookup reports exactly
  that effective locale; and
- respond to dynamic platform locale-list changes through the existing
  `WidgetsApp` observer without restarting the runtime or replacing renderer
  node identity.

This change does not add Dart host overrides for supported locales,
localization delegates, or resolution callbacks. It also does not change the
pre-presentation loading path, which remains outside the internal
`MaterialApp`; the locale contract begins with the first accepted application
presentation.

The locale set and resolution callback must be tested directly rather than
relying only on a manually supplied outer `MaterialApp`, because the inner app
is the authoritative localization boundary. Tests should update
`tester.binding.platformDispatcher.localesTestValue`, observe the inner
`Localizations.localeOf` and `Directionality.of`, decode the emitted
`EnvironmentSnapshot.locale`, and then switch back to English while retaining
the same root State, runtime session, native node State, modal route, draft,
controller, and focus.

Expected implementation scope includes
`flutter/packages/bonsai_flutter/pubspec.yaml`,
`lib/src/root/bonsai_flutter_root.dart`, root/environment tests, and maintained
localization documentation. `EnvironmentReporter` should not bypass the
effective app locale by unconditionally reading `PlatformDispatcher`. No OCaml
environment shape, protocol codec, native widget schema, file under `spec/`, or
Dune file should change.

## Decision

`BonsaiFlutterRoot` owns localization for every language supported by
`GlobalMaterialLocalizations`. Its internal `MaterialApp` installs the global
Material, Cupertino, and Widgets delegates and resolves the first supported
platform-preferred locale while retaining the complete platform language,
script, and country tag. Unsupported languages fall back to English.

That single effective locale drives `Localizations`, `Directionality`, native
framework resources, `EnvironmentReporter`, and the OCaml environment payload.
The change adds no host customization API and does not cover the loading state
before the first accepted presentation. Dynamic locale changes retain runtime,
renderer node, composer State, route, draft, controller, and focus identity.

## Alternatives considered

### Report `PlatformDispatcher.instance.locale` unconditionally

This would make the OCaml payload say `ar-SA`, but the widget tree would remain
English and LTR. It creates two locale authorities and fails native/OCaml layout
consistency.

### Add RTL `Directionality` without localization delegates

Direction alone would not fix `Localizations.localeOf`, Material strings, date
and number conventions, or the environment payload. A manually maintained RTL
language set would also duplicate Flutter's localization data.

### List RTL locales but keep the default delegates

Locale resolution could select Arabic, but `DefaultWidgetsLocalizations`
always returns LTR and `DefaultMaterialLocalizations` remains English. Valid
multilingual support requires global delegates as well as supported locales.

### Normalize every locale to language only

`Locale('ar')` is enough to select RTL resources, but it fails the explicit
requirement that `ar-SA` remain the effective and reported locale. Script and
country subtags can also affect resource selection.

### Expose locale ownership entirely to the embedding Flutter host

The root currently creates its own authoritative `MaterialApp`; an outer app
cannot configure the inner app's supported locales. Requiring every host to
duplicate localization configuration would not fix the standalone root.

## Acceptance criteria

- With platform locale `ar-SA`, the inner root resolves `ar-SA`,
  `Directionality.of` is RTL, and the emitted `EnvironmentSnapshot.locale` is
  exactly `ar-SA`.
- `fa-IR`, `he-IL`, and `ur-PK` satisfy the same locale and RTL assertions.
- A supported LTR locale resolves with its full effective tag and LTR
  directionality; an unsupported locale uses the documented English fallback.
- Dynamic `en-US -> ar-SA -> en-US` changes update localizations,
  directionality, native leading/trailing layout, and one semantic environment
  event per effective change.
- Dynamic locale updates do not restart or dispose the runtime, replace the
  `BonsaiFlutterRoot` State, change renderer node identity, recreate
  `ExpandableMessageComposer` State, dismiss its route, alter its exact draft,
  replace its controller/focus node, or lose focus.
- Global Material and Cupertino localizations are available for the same
  effective locale; modal barrier labels and other native framework strings do
  not fall back independently to English.
- Text scale 3.2 and RTL can be active in the same environment snapshot and
  widget tree.
- Tests clear all platform-dispatcher test values in teardown so locale state
  cannot leak into unrelated widget tests.
- Dart formatting, Flutter analysis, focused root/environment/composer tests,
  the complete Flutter package tests, and `spec-dev-tool check --all` pass.

## Risks

- Adding `flutter_localizations` and global Material translations increases the
  dependency and compiled localization surface of the renderer package.
- Preserving arbitrary region/script subtags requires a resolution rule that
  never returns a locale unsupported by one of the installed delegates.
- Asynchronous localization loading can affect pump counts and transient
  frames in existing root tests.
- An app-specific translation delegate cannot currently be supplied through
  the OCaml application theme contract; framework-global resources may not be
  sufficient for future product strings.
- The pre-presentation loading path currently hard-codes LTR outside any
  `MaterialApp`, so a whole-lifecycle RTL guarantee would require additional
  startup behavior beyond the reported post-presentation bug.

## Questions

None. The user selected all globally supported Material languages,
framework-owned resolution without host overrides, no pre-presentation loading
scope, and preservation of the full supported platform locale tag.

## Consequences

- The renderer package now depends on Flutter's SDK-provided
  `flutter_localizations` package. The internal `MaterialApp` installs the
  global Material, Cupertino, and Widgets delegates.
- Locale resolution preserves the complete first supported platform tag and
  falls back to `en-US` for unsupported languages. The resolved locale drives
  native resources, `Directionality`, and the environment event.
- Dynamic locale tests cover Arabic, Farsi, Hebrew, Urdu, French, script-tagged
  Chinese, unsupported fallback, unchanged-effective-locale suppression, and
  root and renderer State identity.
- Localization documentation, Flutter formatting, and analysis pass, and all
  460 Flutter package tests pass.
