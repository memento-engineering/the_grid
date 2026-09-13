import 'dart:async';

import 'package:beads_dart/beads_dart.dart';

import '../domain/external_dep.dart';
import 'snapshot_source.dart';

/// One federation member's freshness (tg-nsj, `docs/SCRATCH-multi-root-federation.md`
/// D-F3/D-Z3/D-Z4) — the per-member VECTOR [FederatedSnapshotSource.freshness]
/// exposes instead of collapsing every member into one scalar `capturedAt`.
class MemberFreshness {
  /// Creates the freshness record for one member.
  const MemberFreshness({required this.capturedAt, required this.stale});

  /// The member's last known snapshot capture time, or `null` before its
  /// first baseline arrives.
  final DateTime? capturedAt;

  /// True while the member counts as stale for READY purposes — its stream
  /// errored and has not recovered (D-Z4), or its latest capture aged past
  /// the ready-stale window (tg-zd4v). Its last known snapshot is RETAINED
  /// either way (absence ≠ deletion, D-Z3) but mints no NEW ready ids.
  final bool stale;
}

/// Unions N **local** work [SnapshotSource]s into ONE change-gated
/// [SnapshotSource] — the fan-in that runs BEFORE `StationJoinBridge` (D-F1).
///
/// Scope note (`docs/SCRATCH-grid-alignment.md` §4 rescope, 2026-07-03): a
/// remote substation is **never** a snapshot member (D-A2 — assignment-
/// federation, not observation-federation); every member here is a LOCAL
/// beads workspace this station reads directly. Bead ids are prefix-disjoint
/// across stores (measured 2026-07-03: zero cross-prefix collisions), so
/// member snapshots merge directly — no id-rewrite/namespacing needed.
///
/// Membership is MUTABLE (D-F1/D-Z1/D-Z2): [addMember]/[removeMember] attach
/// or detach a member at runtime; the static `--workspace <substation>=<path>`
/// flags `grid_cli` wires at boot are merely the FIRST membership source — a
/// future zero-conf browser is the second, behind this same seam, with
/// nothing here reshaped.
///
/// Contract (matches [SnapshotSource] exactly, so the bridge cannot tell a
/// federated source from a single runtime): [snapshots] is change-gated
/// (diff-non-empty), broadcast, non-replaying; [current] is the last computed
/// union, or `null` before any member has published a baseline.
class FederatedSnapshotSource implements SnapshotSource {
  /// Builds a union over the initial [members] (substation NAME → its own
  /// local [SnapshotSource]) and starts following every one of them
  /// immediately.
  ///
  /// [memberPrefixes] gives each member's bead-id PREFIX by name
  /// (`the_grid` → `tg`); a member absent from the map keeps its name as its
  /// prefix (the `tg` precedent, mirroring `SubstationWorkSpec.prefix`). An
  /// `external:` row resolves its project by member NAME (tg-xh5d); the prefix
  /// rides the armed-roster line so a refusal tells an operator which token
  /// each store answers to.
  ///
  /// [scheduleTimer] is the injectable one-shot deadline seam for age-based
  /// ready staleness. It defaults to [Timer.new].
  FederatedSnapshotSource(
    Map<String, SnapshotSource> members, {
    Map<String, String> memberPrefixes = const {},
    void Function(String message)? onUnresolvedExternalDep,
    Duration? readyStaleAge,
    DateTime Function() now = DateTime.now,
    Timer Function(Duration, void Function())? scheduleTimer,
    void Function(String name, Map<String, String> data)? onFlare,
  }) : _onUnresolvedExternalDep = onUnresolvedExternalDep,
       _readyStaleAge = readyStaleAge,
       _now = now,
       _scheduleTimer = scheduleTimer ?? Timer.new,
       _onFlare = onFlare {
    members.forEach(
      (name, source) => _attach(name, source, memberPrefixes[name] ?? name),
    );
    _current = _combine();
    _scheduleStalenessDeadline();
  }

  /// The LOUD sink for an `external:` row naming a project this station does
  /// not arm — the Q4 HARD refusal. Every OTHER external row is an ordinary
  /// blocker and says nothing.
  final void Function(String message)? _onUnresolvedExternalDep;

  /// The age past which a member's snapshot stops minting NEW ready ids
  /// (tg-zd4v face 2) — a bounded multiple of the sync floor, or null to
  /// judge staleness by stream error only (the pre-floor behavior).
  ///
  /// Age is judged at every [_recompute]. Member events re-arm one exact
  /// deadline for the earliest possible age edge, so even an entirely quiet
  /// federation advances staleness on time. With the floor in place a healthy
  /// member re-captures every tick; reaching the window means the member has
  /// GENUINELY gone quiet — the exact state that produced the stale mint.
  final Duration? _readyStaleAge;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _scheduleTimer;
  Timer? _stalenessTimer;
  bool _disposed = false;

  /// The rising-edge staleness flare sink (tg-zd4v face 3): fires ONCE when a
  /// member goes stale by age (`sync.memberStaleByAge`) and ONCE when it
  /// recovers (`sync.memberRecovered`). Stale-by-ERROR and probe death are
  /// tg-dwyl's, already flared elsewhere — never re-emitted here.
  final void Function(String name, Map<String, String> data)? _onFlare;
  final Set<String> _ageStale = {};

  final Map<String, SnapshotSource> _sources = {};

  /// Each member's bead-id PREFIX by member name, defaulting to the name.
  final Map<String, String> _prefixOf = {};

  /// External rows already refused, keyed by [ExternalDepRefusal.edgeKey] —
  /// the rising-edge dedupe that keeps one authored row to ONE log line
  /// however often the union recomputes.
  final Set<String> _refusedDepRows = {};

  final Map<String, StreamSubscription<GraphSnapshot>> _subs = {};
  final Map<String, GraphSnapshot?> _latestByMember = {};
  final Map<String, bool> _staleByMember = {};

  final StreamController<GraphSnapshot> _controller =
      StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;

  /// The member substation ids currently unioned (read-only view).
  Set<String> get members => Set.unmodifiable(_sources.keys);

  /// The per-member freshness vector (D-F3) — the union's own `capturedAt`
  /// (on the combined [GraphSnapshot]) is the MAX of these; staleness is
  /// judged per member, never averaged away.
  Map<String, MemberFreshness> get freshness => {
    for (final id in _sources.keys)
      id: MemberFreshness(
        capturedAt: _freshCapturedAt(id),
        stale: _isStale(id),
      ),
  };

  /// The member's freshest known capture time — the LIVE source's `current`
  /// first, the last PUBLISHED snapshot as fallback.
  ///
  /// The distinction is load-bearing (the first-night regression): a healthy
  /// floor refresh against an UNCHANGED store advances the runtime's
  /// `current.capturedAt` but publishes nothing (change-gated), so judging
  /// age off the published snapshot alone ages every quiet-but-healthy member
  /// into ready-staleness at 3x floor and silently shrinks the frontier
  /// (observed live 2026-08-07: ready 16 → 4 within minutes of arming).
  /// Content still comes from the published snapshot — only the AGE
  /// judgement reads the live heartbeat.
  DateTime? _freshCapturedAt(String id) =>
      _sources[id]?.current?.capturedAt ?? _latestByMember[id]?.capturedAt;

  /// The exact instant at which [id]'s freshest known capture becomes stale.
  DateTime? _ageDeadline(String id) {
    final age = _readyStaleAge;
    final capturedAt = _freshCapturedAt(id);
    if (age == null || capturedAt == null) return null;
    return capturedAt.add(age);
  }

  /// Whether [id] has reached its age deadline at [instant].
  bool _isAgeStaleAt(String id, DateTime instant) {
    final deadline = _ageDeadline(id);
    return deadline != null && !instant.isBefore(deadline);
  }

  /// A member is stale for READY purposes when its stream errored (D-Z4) OR
  /// its freshest known capture has aged past [_readyStaleAge] (tg-zd4v).
  /// Its beads stay visible either way (D-Z3 — absence is not deletion).
  bool _isStale(String id) {
    if (_staleByMember[id] == true) return true;
    return _isAgeStaleAt(id, _now());
  }

  /// Detects age-staleness EDGES and flares each exactly once. Runs before
  /// every combine so the judgement is as fresh as the union it gates.
  void _flareAgeEdges() {
    final sink = _onFlare;
    if (_readyStaleAge == null) return;
    final now = _now();
    for (final id in _sources.keys) {
      final capturedAt = _freshCapturedAt(id);
      final staleNow = _isAgeStaleAt(id, now);
      if (staleNow && _ageStale.add(id)) {
        final staleCapturedAt = capturedAt!;
        sink?.call('sync.memberStaleByAge', {
          'substation': id,
          'capturedAt': staleCapturedAt.toIso8601String(),
          'ageSeconds': '${now.difference(staleCapturedAt).inSeconds}',
          'windowSeconds': '${_readyStaleAge.inSeconds}',
        });
      } else if (!staleNow && _ageStale.remove(id)) {
        sink?.call('sync.memberRecovered', {
          'substation': id,
          if (capturedAt != null) 'capturedAt': capturedAt.toIso8601String(),
        });
      }
    }
  }

  /// Re-arms one timer for the earliest future age-staleness edge. Members
  /// without a capture and members already stale by age have no future edge,
  /// so they contribute no deadline.
  void _scheduleStalenessDeadline() {
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    if (_disposed || _readyStaleAge == null) return;

    final now = _now();
    DateTime? earliest;
    for (final id in _sources.keys) {
      final deadline = _ageDeadline(id);
      if (deadline == null || !deadline.isAfter(now)) continue;
      if (earliest == null || deadline.isBefore(earliest)) {
        earliest = deadline;
      }
    }
    if (earliest == null) return;

    late final Timer timer;
    timer = _scheduleTimer(earliest.difference(now), () {
      if (!identical(_stalenessTimer, timer)) return;
      _stalenessTimer = null;
      if (_disposed) return;
      _recompute();
    });
    _stalenessTimer = timer;
  }

  /// Attaches a NEW member at runtime (D-Z1/D-Z2 — mutable membership; a
  /// future zero-conf browser calls this behind the same seam a static
  /// boot-time list uses today). [prefix] is the member's bead-id prefix,
  /// defaulting to [substation]. A no-op if [substation] is already a member.
  void addMember(String substation, SnapshotSource source, {String? prefix}) {
    if (_sources.containsKey(substation)) return;
    _attach(substation, source, prefix ?? substation);
    _recompute();
  }

  /// Detaches a member — an operator un-registering a store, not a network
  /// blip (that's a stream error, handled by [_attach]'s `onError`, which
  /// keeps the member and only marks it stale — absence ≠ deletion, D-Z3).
  /// A no-op if [substation] is not a member.
  void removeMember(String substation) {
    final sub = _subs.remove(substation);
    if (sub == null) return;
    unawaited(sub.cancel());
    _sources.remove(substation);
    _latestByMember.remove(substation);
    _staleByMember.remove(substation);
    _prefixOf.remove(substation);
    _recompute();
  }

  void _attach(String substation, SnapshotSource source, String prefix) {
    _sources[substation] = source;
    _prefixOf[substation] = prefix;
    _latestByMember[substation] = source.current;
    _staleByMember[substation] = false;
    _subs[substation] = source.snapshots.listen(
      (snapshot) {
        _latestByMember[substation] = snapshot;
        _staleByMember[substation] = false;
        _recompute();
      },
      onError: (Object _, StackTrace _) {
        // D-Z3 — absence ≠ deletion: RETAIN the last known snapshot frozen;
        // only mark the member stale (D-Z4 handles what staleness costs).
        _staleByMember[substation] = true;
        _recompute();
      },
    );
  }

  void _recompute() {
    _flareAgeEdges();
    final previous = _current;
    final next = _combine();
    _current = next;
    if (next != null && diffSnapshots(previous, next).isNotEmpty) {
      _controller.add(next);
    }
    _scheduleStalenessDeadline();
  }

  /// Merges every member's latest known snapshot into one [GraphSnapshot]:
  /// beads/dependencies union directly (ids are prefix-disjoint); readyIds is
  /// the union of FRESH members' ready ids (D-Z4 — a stale member mints no
  /// NEW ready ids, though its already-known beads stay visible above),
  /// narrowed by every unsatisfied `external:` dependency row (tg-xh5d).
  /// Returns `null` while no member has ever published (no baseline anywhere
  /// yet).
  GraphSnapshot? _combine() {
    if (_latestByMember.values.every((s) => s == null)) return null;

    final beadsById = <String, Bead>{};
    final dependencies = <BeadDependency>[];
    DateTime? capturedAt;
    final readyCandidates = <String>{};

    for (final entry in _latestByMember.entries) {
      final snapshot = entry.value;
      if (snapshot == null) continue;
      beadsById.addAll(snapshot.beadsById);
      dependencies.addAll(snapshot.dependencies);
      if (capturedAt == null || snapshot.capturedAt.isAfter(capturedAt)) {
        capturedAt = snapshot.capturedAt;
      }
      if (!_isStale(entry.key)) {
        readyCandidates.addAll(snapshot.readyIds);
      }
    }

    return GraphSnapshot(
      beadsById: beadsById,
      dependencies: dependencies,
      readyIds: _admitExternalDeps(dependencies, readyCandidates),
      capturedAt: capturedAt!,
    );
  }

  /// Honours bd's NATIVE cross-project dependency rows (tg-xh5d,
  /// `the_grid#the-grid-is-a-beads-controller`): a row on
  /// `external:<project>:<capability>` holds its consumer out of ready until
  /// the named member's store holds a CLOSED bead labelled
  /// `provides:<capability>` — the fact `bd ship` writes.
  ///
  /// `<project>` resolves by ROSTER NAME (bd resolves the same token through
  /// its own `external_projects` config; the two maps are the same roster).
  /// A project this station does not arm is the LOUD Q4 hard-refusal: the
  /// consumer is held out fail-closed AND reported, because an edge naming a
  /// store the station is not arming must never pass as satisfied.
  ///
  /// An ordinary same-store row is left untouched — the origin store's own
  /// `bd ready` already governs it — and an ARMED-but-unshipped capability
  /// blocks silently, exactly as an open local blocker does.
  ///
  /// Rising-edge: one line per refused row (by [ExternalDepRefusal.edgeKey])
  /// for as long as the row is observed; a row that disappears and returns is
  /// reported again.
  Set<String> _admitExternalDeps(
    List<BeadDependency> dependencies,
    Set<String> candidates,
  ) {
    final verdict = applyExternalDeps(
      candidates: candidates,
      dependencies: dependencies,
      isArmed: _sources.containsKey,
      isShipped: _capabilityShipped,
    );
    final observed = <String>{};
    for (final refusal in verdict.refusals) {
      observed.add(refusal.edgeKey);
      if (!_refusedDepRows.add(refusal.edgeKey)) continue;
      _onUnresolvedExternalDep?.call(refusal.message(_armedRoster));
    }
    _refusedDepRows.retainAll(observed);
    return verdict.admitted;
  }

  /// Whether [project]'s OWN member snapshot proves [capability] shipped.
  ///
  /// Scoped to the named member rather than the union: a capability is shipped
  /// BY a project, so a same-named label in some other store must never
  /// satisfy it.
  bool _capabilityShipped(String project, String capability) {
    final snapshot = _latestByMember[project];
    if (snapshot == null) return false;
    return capabilityShipped(capability, snapshot.beadsById.values);
  }

  /// The armed roster as `name(prefix)` pairs — the operator-facing answer to
  /// "which stores could have resolved this id?".
  String get _armedRoster => [
    for (final name in _sources.keys) '$name(${_prefixOf[name] ?? name})',
  ].join(', ');

  /// Cancels every member subscription and closes the union stream. Does
  /// **not** dispose the member [SnapshotSource]s themselves — the caller
  /// that built them (`buildControllers`) owns their lifecycle.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
    await _controller.close();
  }
}
