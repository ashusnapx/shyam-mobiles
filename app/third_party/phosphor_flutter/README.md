# phosphor_flutter (vendored)

Upstream 2.1.0 (latest on pub.dev as of 2026-10-29) breaks on Flutter 3.47: `IconData` is now a
`final class`, and upstream extends it. This copy rewrites every icon to `IconData(codePoint, fontFamily: 'Phosphor<Style>',
fontPackage: 'phosphor_flutter')` and keeps Regular, Fill, Bold and Light. Same names, so app code doesn't change.

shortcut: drop this folder and the `dependency_overrides` entry in app/pubspec.yaml once upstream ships a fix.
