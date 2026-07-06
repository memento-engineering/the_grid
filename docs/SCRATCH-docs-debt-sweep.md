# SCRATCH — the docs & debt sweep (glossary review → holistic cleanup)

**Status: active surface.** Opened 2026-07-05 after Nico's review of `docs/GLOSSARY.md`
(itself the first artifact of this pass). This doc is the durable home for: (1) the
**rulings log** from that review, (2) the **detailed drift/conflict analysis** the
glossary only summarized, (3) the **holistic config-model plan** graduated from session
chat, and (4) the **sweep worklist**. Scope: docs, terminology, and trash removal only —
**no new code in this pass** (Nico, 2026-07-05).

Evidence base: an 8-surface ultracode research sweep (559 term entries, 57 flows) + a
conflict audit + a completeness critique; raw digests in the session scratchpad
(`glossary/{terms_digest,flows_digest,conflicts,gaps}.md`), full per-agent returns in the
workflow journal (`wf_d09bf3fe-02f`).

---

## 1. Rulings log (Nico, 2026-07-05, reviewing GLOSSARY.md)

- **R1 · lenny de-emphasis.** lenny/leonard is the debugging arm of the **org**, not of
  the grid. Both lenny and the_grid are genesis consumers and may share genesis patterns,
  but `grid_engine` and lenny must avoid emphasizing any coupling. the_grid's core docs
  stop treating lenny prominence as load-bearing; attach/debug material moves to
  testing/debugging docs (R14).
- **R2 · Grid = a deployment.** "Grid (federation)" is too narrow: a Grid can be an
  unfederated single-station deployment. Better framing: **a deployment / an instance**
  of the system (one station or many).
- **R3 · Asset is broad.** Nico's usage includes **any component of the system** —
  station, substation, circuits, capabilities, scopes, nodes — as well as a node's own
  assets. The ADR-0011 pack/resource taxonomy is a subset of this broader usage, not the
  boundary of the word.
- **R4 · Workspace collapses into substation.** "Why not just substation?" — a
  substation registration should carry its store path; a separate "workspace" term (and
  flag axis) is redundant. Folds into the config redesign (§3).
- **R5 · Resident is the only model.** `grid run` is deleted; a station IS resident.
  "Resident station" stops being special vocabulary; the arming ladder loses its
  run-vs-resident split conceptually.
- **R6 · agent homonym: not managed.** The lenny-vs-grid "agent" clash is the English
  language + industry usage; not a conflict the org resolves. Drop it from the drift
  ledger.
- **R7 · session = the activation.** In the grid, a **session is the activation around a
  bead in the tree** — the scopes and capabilities that bring the work to life. The
  session *bead* is the durable record of one activation. (The prior glossary framing —
  session ≡ the bead — was wrong or at best backwards.)
- **R8 · Circuit, everywhere.** "Formula" survives **only** in gas-city
  transition/compat prose explaining what circuits are in relation to gc; all current
  vocabulary is Circuit. (Stamp debt on ADR-0008 — worklist W2.)
- **R9 · the grid vs grid_sdk, resolved.** `the_grid` / "The Grid" / "the grid" = the
  **framework as a concept** ("What orchestrator are you using?" — "I'm running the
  grid."). **`grid_sdk`** = the framework as **concrete code** — the core package
  consumers build against ("I built my system using the grid sdk."). This resolves the
  ADR-0008 D1 vs M5 D-SDK naming tension in favor of `grid_sdk` for the package.
- **R10 · "virtual substation" dropped.** The term is dead. Remote stations that this
  system observes are **stations observed as assets** — nothing more.
- **R11 · rig, like Formula.** "rig" survives only in gc-compat/transition prose;
  everywhere else, Substation. (Prose-residue sweep — worklist W4.)
- **R12 · No plugins, org-wide.** memento.engineering uses **extensions** unless
  literally building Flutter Plugins. The `GridControllerPlugin` naming was another
  instance of lenny driving grid decisions.
- **R13 · Emptied stubs: delete.** `packages/{grid_controller,grid_reconciler,
  grid_federation}` husks removed (**done** 2026-07-05 — they held only untracked `.iml`
  files; the workspace pubspec had already dropped them).
- **R14 · defaultSubstation: not a concept that should exist.** Confirms the config
  redesign direction (§3).
- **R15 · Boot should be `runGrid`-shaped.** The station-runner pieces are "entirely too
  free-form, library-level function oriented." Target shape: `runGrid(delegate)` — or
  `runGridDelegate` — where the delegate is an **observable object** plumbed into a
  `Grid` instance that drives it. The delegation pattern itself is documented in §3.2a.
  Cleanup deferred — design target recorded here.
- **R16 · ServiceBundle is on notice.** "Why are we still using ServiceBundles??" — see
  §2.9 for the honest answer and disposition (dissolve in the config redesign).
- **R17 · F8 (attach/observe) out of core docs** — testing/debugging documentation, not
  the glossary/core set.

---

## 2. Drift & debt — the detailed analysis

Each item: evidence → scope → disposition (per §1 rulings).

### 2.1 Formula → Circuit stamp debt
**Evidence:** `grid_engine/lib/src` contains **zero** occurrences of `Formula`; the
authoring surface is `Circuit` (`sdk/circuit.dart:230`, sealed `CircuitStep.capability` /
`CircuitStep.subCircuit`, verb "energize"). The rename was RS-7, ratified in
`SCRATCH-resident-station` §6/§9 — which itself notes forward-pointer stamps on ADR-0008
are **owed and unapplied**. ADR-0008 still says "Formula" ~29×.
**Scope:** one supersession stamp on ADR-0008 (quote-and-supersede, one banner — not 29
rewrites); optional one-line pointers in M4-P1 build order.
**Disposition (R8):** apply the stamp in this sweep (W2). Formula survives only in
gc-compat prose.

### 2.2 Observation-federation residue in vnext-prd
**Evidence:** `SCRATCH-vnext-prd.md` §5 (~lines 329–345) still presents "virtual
substations" + the observed-Grid-view model as proposed-live. `SCRATCH-grid-alignment`
D-A2 (ratified 2026-07-03): "Assignment-federation, never observation-federation. A
remote substation is NEVER a snapshot member of my station." `SCRATCH-multi-root-
federation` already records "D-Z7 is dead (D-A2)".
**Scope:** one supersession banner on vnext-prd §5.
**Disposition (R10):** stamp it (W3); the replacement language is "stations observed as
assets" — no new term.

### 2.3 rig prose residue
**Evidence:** class-level rename clean (0 hits for the old class names), but "rig" is the
live noun in doc-comments across `station_seed.dart` (6, 9–11), `substation.dart` (6–7,
15), `substation_scope.dart` (9, 12, 39), `work_list.dart` (34, 130, 134, 273),
`substation_config_notifier.dart` (5), `engine_fakes.dart` (440, 487).
**Distinct and deliberate (law, not residue):** the persisted codec key `metadata.rig`
(`StationBeadWriter.rigKey`), gc's convergence byte-port schema, `IssueType.rig`.
**Scope:** a comments-only sweep across ~6 engine files; zero behavior.
**Disposition (R11):** sweep the prose (W4); never touch the codec boundary.

### 2.4 plugin / GridController* residue
**Evidence:** `grid_exploration/lib/src/grid_controller_plugin.dart` ships
`class GridControllerPlugin` with prose "The grid plugin…" (lines 20–67) — against A33
(extensions) and D-A6 (beads_dart rename). `beads_dart/lib/src/reactivity/
grid_controller_runtime.dart` ships `class GridControllerRuntime` inside the renamed
package. The handshake also reports `bindingType:'GridControllerHost'` (wire-visible —
check compat before renaming that one).
**Scope:** symbol + file renames in two packages; tg-cxw already covers the beads_dart
half; the exploration half is uncovered. Renames are CODE, not docs.
**Disposition (R12):** docs/comments fixes ride this sweep where prose-only; the symbol
renames fold into tg-cxw (widen it) and wait for the coding lane — not this pass.

### 2.5 Emptied package stubs — DONE
**Evidence:** `packages/{grid_controller,grid_reconciler,grid_federation}` contained only
untracked `melos_*.iml`; workspace pubspec listed none of them.
**Disposition (R13):** deleted 2026-07-05. No git change resulted (nothing tracked).

### 2.6 ADR-0002 topology staleness
**Evidence:** ADR-0002 D1 still describes grid_controller as the M1 SDK package and
doesn't reflect: beads_dart rename, grid_reconciler deletion, grid_federation dissolution
into `federated_grid_assets`, the `grid_sdk` naming (R9).
**Scope:** an amendment section on ADR-0002 (quote-and-supersede) once Nico wants it —
package-topology amendments are ratification-grade.
**Disposition:** drafted as part of this sweep's output for Nico's sign-off (W6); not
silently edited.

### 2.7 session terminology
**Evidence:** docs + glossary defined session ≡ the durable lifecycle bead. R7 corrects:
**session = the activation** (SessionScope + the capability subtree animating one bead);
the bead is the *record* of an activation. Code names align acceptably
(`SessionScope`, session bead) — the fix is documentation framing, not symbols.
**Disposition:** glossary updated (done, this sweep); future docs use
activation-vs-record framing.

### 2.8 workspace / resident / defaultSubstation (config-surface vocabulary)
**Evidence:** three terms that exist only because the config surface grew by delta:
"workspace" as a separate axis (R4: collapse into substation registration), "resident" as
a special mode (R5: it's the only mode; `grid run` is gone — verified: `bin/grid.dart`
registers only watch/gate/rework/demo), and defaultSubstation/`substations.first`
(R14: shouldn't exist — see §3).
**Disposition:** vocabulary corrected in the glossary now; the surface itself is
redesigned per §3 (code later, not this pass).

### 2.9 ServiceBundle — why it exists, and why it's on notice
**The honest why:** ADR-0008 D5 made SourceControl a per-substation service; tg-7gm then
needed per-*root* resolution, so the bundle grew `sourceControlsByRoot` +
`sourceControlFor(bead)`. It became a string-keyed DI grab-bag — keyed by substation id,
constructed in space_station via `serviceBundleMapFor(defaultSubstation: …)`. It is the
same D-M5 disease as defaultSubstation: a **name-keyed map standing in for tree-scoped
provision**, bolted on where the tree already has the right mechanism (typed ambient
values + DI per concern, per D-H: config = values in the tree, impls = DI).
**Disposition (R16):** dissolve with the config redesign (§3): the delegate provides
impls per concern (ordered build hooks), the tree provides values; no string-keyed
bundles. Not this pass.

### 2.10 The A37 split in practice
Ruled model (Nico, 2026-07-05): **one store per station** (its state store) and **one
store per substation** (its work source). A station hosting N substations therefore reads
N work stores and writes exactly one state store. Today's lived shape is the N=1 case
(work `tg`, state `tgdog`); the N>1 machinery (tg-nsj union) exists in code and tests,
with its live arms deferred pending grooming.

---

## 3. The config-model redesign (graduated from chat, updated with R4/R5/R14/R15/R16)

### Root causes (from the 2026-07-04 forensic pass — evidence in session record)
1. **Compat conservatism as spec default** — my bead specs said "back-compatible" /
   "byte-identical generalization" (tg-7gm, tg-nsj verbatim) though Nico had ruled
   no-back-compat (no shipped users). Agents built exactly what the specs said.
2. **Delta-specs against existing code, not derivations from the ratified model** — the
   substation-id/root-name pun was in my spec (`--root <substation>=<path>`) and in the
   surface doc ("substation's own name = its default root"); D-M1's 1:N amendment never
   re-derived the config surface.
3. **Fallback-instead-of-refuse in underspecified edges** — `.first` chains, `''`
   sentinel keys, cwd discovery (violates the guard principle at the config layer).

### The plan
1. **Ratify the config model.** Axes: ownership (substations), source control (roots),
   stores (per-substation registration — no separate "workspace" axis, R4). Explicit
   joins; **no ambient defaults anywhere**; unspecified routing input = loud refusal.
   No run-vs-resident split (R5). Supersede "substation's own name = its default root"
   with a stamp.
2. **One rebuild unit, not patches** — targeting the R15 shape: **`runGrid(delegate)`**
   per the delegation pattern (§3.2a); the station-runner pieces become delegate hooks;
   **ServiceBundle dissolves** into per-concern DI + config-values-in-the-tree (R16);
   space_station's hand-mirror collapses into a delegate subclass (the drift class dies
   structurally — absorbs tg-da7); bare grammars / sentinels / `.first` chains / compat
   aliases deleted.

### 3.2a The delegation pattern (the R15 target, on its own terms)

A composition discipline for frameworks that boot a long-lived reactive system:

*(Corrected 2026-07-05 after Nico's v1 review — the hooks are TREE-BUILDING methods,
not opaque factories. Canonical statement: `SCRATCH-station-config-model.md` §2.)*

1. **The framework root is `final`.** Consumers never subclass the running machine;
   all consumer behavior enters through a delegate. This finishes ADR-0008 D2's
   "compose, never subclass" at the boot seam.
2. **One entry point:** `runGrid(GridDelegate delegate)`. The delegate is *provided
   into the tree* and observed there.
3. **The delegate is itself observable** — a `StateNotifier<GridConfiguration>`, where
   the configuration is a **set of typed config domains** observed **by aspect**: a
   change to one domain rebuilds only that domain's observers. Runtime mutation flows
   as state emission through the same reconcile path as any observed change — no
   restart, no re-parse.
4. **Hooks are build methods on rails:** `build*(context, child) → tree-layer`, chained
   **by the framework inside the tree** — each hook's output is an ancestor of the next,
   `@mustCallSuper` with super-first wrapping, every hook default-implemented. The
   framework owns order and nesting; the consumer owns only the layers it overrides.
   Hooks run in the tree, so they observe config domains and ambient values like any
   build method. The master hook builds the `Grid(Station(substations: […]))` subtree
   from the configuration.
5. **Conditional layers are reconcile-driven** — a gated block (armed/live vs dry)
   mounts and unmounts off observed state, the way an authenticated-dependencies layer
   mounts on auth state; never boot-time if/else.
6. **Errors at hooks are captured, attributed, and loud** — a failed hook is a named
   refusal (guard principle), never a stack trace from library plumbing.

Consequences: `space up` becomes a delegate subclass with its own CLI (the hand-mirror
dies structurally); `grid_cli`'s verbs implement the same model — **no backporting, no
shimming**; tests construct a delegate over fakes; "flags vs TOML vs code" becomes
"how does this delegate build its initial `GridConfiguration`" (BOTH TOML and Dart are
first-class sources), decoupled from boot.
3. **Fossil audit first** — read-only sweep for `.first`/sentinel/fallback/alias across
   grid_cli, grid_engine, grid_runtime, space_station feeding the rebuild spec.
4. **Process fixes** (standing rules for every spec Fable authors):
   no back-compat before first publish; "byte-identical generalization" is a banned spec
   phrase — generalization beads derive from the model and delete the fossil, test
   migration in scope; every spec touching a ratified-model seam quotes the model clause
   it implements.

Sequencing: docs sweep (this pass) → Nico ratifies the config model → fossil audit →
rebuild unit (with tg-d7z ordered ahead of or inside it — its fan-out kills the last
single-root consumer).

---

## 4. Worklist

- [x] **W0** GLOSSARY.md authored; corrected per §1 rulings (2026-07-05).
- [x] **W1** Delete emptied package stubs (R13). *(2026-07-05; untracked `.iml` only.)*
- [x] **W2** ADR-0008 Formula→Circuit supersession stamp applied (cites RS-7; also the
      D1 `grid_sdk` naming revision per R9). *(2026-07-05 — stamp execution of ratified
      decisions; Nico reviews.)*
- [x] **W3** vnext-prd §5 supersession banner applied (D-A2; "virtual substation"
      dropped per R10). *(2026-07-05.)*
- [x] **W4** rig prose-residue sweep in grid_engine doc-comments — 9 files (the audit's
      6 plus `station_services.dart`, `substation_config.dart`, `work_list.dart:34`);
      freezed regen + `dart analyze` clean; codec boundary + bd's literal
      `rig` issue-type mentions untouched. *(2026-07-05.)*
- [x] **W5** `docs/DEBUGGING.md` created (attach/observe flow, exploration verbs,
      client-agnostic framing); GLOSSARY §10/F8 trimmed to pointers; core docs
      de-leonarded. *(R1, R17; 2026-07-05.)*
- [x] **W6** ADR-0002 topology amendment stamp applied (beads_dart rename D-A6/D-A7,
      grid_reconciler deletion D-A5/RS-8, grid_federation → federated_grid_assets,
      `grid_sdk` naming R9, stub removal R13, live workspace list). *(2026-07-05 —
      stamp execution of ratified decisions; Nico reviews.)*
- [x] **W7** tg-cxw widened: + `GridControllerPlugin` rename + "plugin" prose purge +
      the wire `bindingType:'GridControllerHost'` compat caution. Coding-lane bead,
      deferred. *(R12; 2026-07-05.)*
- [x] **W8** Config-model design doc **drafted**: `SCRATCH-station-config-model.md` —
      **PROPOSAL, awaiting Nico** (4 open questions §6). **HARD STOP before any code:**
      Nico (2026-07-05) — the delegate understanding must be confirmed solid before
      implementation; the rebuild unit files only after ratification.
- [x] **W9** Standing rule: GLOSSARY.md is updated at each ratification/unit close
      (owner: Fable). Recorded here; treated as part of the working agreement.
