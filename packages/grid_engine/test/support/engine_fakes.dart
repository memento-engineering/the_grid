// The shared offline fakes were promoted to the public testing-support library
// `package:grid_engine/testing.dart` (the cross-package enabler so grid_assets's
// tests reuse the SAME fakes). This file re-exports it so existing grid_engine
// test imports keep working unchanged.
export 'package:grid_engine/testing.dart';
