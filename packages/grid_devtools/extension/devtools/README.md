# grid_devtools extension build

This directory follows the `devtools_extensions` layout: DevTools loads the
extension from `build/` and reads `config.yaml` for its name + icon.

`build/` is a **placeholder** in M1 (the scaffold ships the panel widget and
the protocol client; the compiled web bundle is regenerated on demand). To
produce the real bundle, from the package root run:

```sh
dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=extension/devtools
```

That compiles the Flutter web app (entrypoint `lib/main.dart`) and copies it
into `build/`, alongside this `config.yaml`. The host process that wants to
surface the extension references this package in its `devtools_options.yaml`.
