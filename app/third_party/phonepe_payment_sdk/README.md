# phonepe_payment_sdk (vendored)

Upstream 3.0.2 (latest on pub.dev as of 2026-11-03, MIT) can't be built with AGP 9: its `android/build.gradle` minifies
the library with `getDefaultProguardFile('proguard-android.txt')`, which AGP 9 refuses at configuration time, so every
build of the app (debug too) fails. This copy replaces that `buildTypes` block with `consumerProguardFiles`
(`-keep class com.phonepe.** { *; }` reaches the app's R8) and raises `compileSdk` from 31 to 36 (its AndroidX
dependencies need 34+, so `checkReleaseAarMetadata` failed too). Everything else is upstream; the example and Gradle wrapper
are left out.

shortcut: drop this folder and the `dependency_overrides` entry in app/pubspec.yaml once upstream ships a fix.
