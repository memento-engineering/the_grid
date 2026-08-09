# Tree Composition Style

These rules are the house style for station and asset authors. They give the existing tree engine a Flutter-shaped composition vocabulary and preserve the decisions in ADR-0007, ADR-0008, and ADR-0000 A39.

## 1. `build*` describes synchronously

A `build*` method returns structure synchronously, with Flutter `WidgetBuilder` semantics. It does not `await`, perform I/O, allocate off-tree runtime machinery, or make lifecycle effects happen. Observe outside `build`; project the observed value inside `build`.

Async assembly must use an assembly verb instead of `build`. The house examples are landed now: `assembleStationWork` (the `tg-1fa2.3` disposition of the old `buildStationWork` name) and the awaited pre-tree `GridDelegate.boot` rail (tg-1fa2.4).

When sweeping a `build*` name, keep synchronous describers unchanged. Rename only async assembly disguised as description. The current-tree sweep found no uncontested rename: `buildDelegate` synchronously returns a `GridDelegate`, while no `buildRunner` or `buildWorkRegistry` symbol exists.

## 2. Provider ownership follows construction

`Provider<T>(create:)` constructs its value inside the tree lifecycle during `initState`, and the tree disposes that value at unmount. `Provider<T>.value` adopts an instance held by another owner, and the tree never disposes it.

Never pass a pre-built instance through `create:`. That falsely assigns ownership to the tree: the tree may dispose a value it did not create, or lifecycle code may leak a value it believes it created.

## 3. Availability is observed, including absence

`context.watch<T>()` always returns `T?`. It registers the dependency edge unconditionally, whether a matching provider is present or absent. Availability notification is bidirectional: provider mount rebuilds dependents from null to value, and provider unmount rebuilds them from value to null.

There is deliberately no throwing `of()` variant. Unavailability is a designed posture. A consumer handles the null arm and renders a refusal into diagnostics; it never converts absence into an exception.

## 4. No provider is universal

A station is not only a code writer, and git is not the only source-control system. `GitServices`, delivery, and comparable capabilities are seat-stack choices supplied at the scope where they apply. Code must not assume that any such provider is universally mounted. Depend on abstract seams, observe availability, and render the absent posture.

## 5. Boot is an assembly ratchet

The live `GridDelegate` API has `didLaunch`, the awaited pre-tree `boot` (tg-1fa2.4), and `initGrid` lifecycle rails — and it is ONE class: `tg-at3r` folded grid_cli's old resident delegate contract (`ResidentGridDelegate`) into grid_sdk's `GridDelegate`, retiring the two-layer delegate split (a station "running resident" is a state, never a type name). Assembly on the rails constructs resources and connects them. Policy belongs in `build`, where the tree projection can observe it. Decisions such as which seats arm, which posture to choose, or whether a refusal skips work are tree policy and must not migrate into lifecycle assembly. The standing exceptions — `GridDelegate.armRoster` and `GridDelegate.stalenessPosture`, whose outcomes are exit codes and the lock decision — are acknowledged ratchet DEBT under this rule (see the `GridDelegate` class doc), not license for new pre-tree policy.

A line belongs on a delegate lifecycle rail only when ADR-0000 A45's pinned ordering requires it: `didLaunch` is synchronous and pre-tree, while `initGrid` is the post-mount asynchronous kickoff. This is a ratchet: new policy does not enter lifecycle assembly, and assembly moves into the tree as lifecycle-capable providers become available.
