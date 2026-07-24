import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cockpit_contract/grid_cockpit_contract.dart';
import 'package:state_notifier/state_notifier.dart';

import '../diagnostics/diagnosable.dart';
import '../domain/substation_config.dart';
import '../notifiers/substation_config_notifier.dart';
import '../sdk/capability.dart';
import 'substation.dart';

/// The per-substation **config scope** — an ancestor of the substation's work nodes
/// (ADR-0007: config nodes are ancestors of work nodes).
///
/// It OBSERVES the substation's [SubstationConfigNotifier] (the config axis, separate from
/// the work/snapshot axis) and re-provides the current [SubstationConfig] ambiently
/// via `InheritedSeed<SubstationConfig>` to the work subtree below it.
///
/// It is ALSO where the substation's [ServiceBundle] is provided (ADR-0008 D5:
/// source control is a SUBSTATION responsibility — a project dictates its own
/// SCM; the station only supplies shared git-execution machinery the substation
/// leases). The bundle is a fixed-at-mount handle: it is provided as a plain
/// `InheritedSeed<ServiceBundle>` (genesis's identity check declines to notify
/// when the same instance is re-provided; to change a substation's services,
/// remount the scope by key — ADR-0008 D-6, superseded 2026-07-02), scoped to
/// THIS substation's subtree: a `CapabilityHost` deep below resolves the
/// NEAREST bundle, so each substation's work runs against its own source
/// control, never a station-wide one. Provided here rather than above
/// `Station` so two substations get isolated bundles.
///
/// Because the config and work axes are observed by *different* nodes, a work
/// tick never rebuilds this scope ([buildCount] stays put), and a config tick
/// never starts/stops a work effect. That separation is the load-bearing claim
/// of ADR-0007 §6.1.
///
/// P0 assumption: the [SubstationConfigNotifier] *instance* is stable for the scope's
/// lifetime (the kernel builds it once). genesis `State` has no
/// did-update-config hook, so a swapped notifier instance would not re-bind;
/// that does not occur in P0.
class SubstationScope extends StatefulSeed with Diagnosable {
  /// Creates a scope driven by [configNotifier], providing [services] to its
  /// subtree. Key it by substation id at the Station level so a substation add/remove
  /// mounts/unmounts exactly this scope.
  const SubstationScope({
    required this.configNotifier,
    this.services = const ServiceBundle(),
    super.key,
  });

  /// The config-axis source this scope observes.
  final SubstationConfigNotifier configNotifier;

  /// This substation's pluggable collaborators (source control / trust /
  /// transport — ADR-0008 D5), re-provided to the work subtree below. Empty by
  /// default (an offline build wires none ⇒ provisioning + land no-op).
  final ServiceBundle services;

  @override
  State<SubstationScope> createState() => _SubstationScopeState();
}

class _SubstationScopeState extends State<SubstationScope> with Diagnosable {
  RemoveListener? _remove;
  late SubstationConfig _config;

  @override
  void initState() {
    // The initial read IS the subscription (D-H rule 2): fireImmediately
    // delivers the baseline synchronously into the listener — assigned directly
    // (no setState during mount); every later fire goes through setState.
    var first = true;
    _remove = seed.configNotifier.addListener((config) {
      if (first) {
        first = false;
        _config = config;
        return;
      }
      setState(() => _config = config);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _remove?.call();
    _remove = null;
  }

  @override
  void debugFillProperties(DiagnosticsBuilder builder) {
    super.debugFillProperties(builder);
    builder.add(
      ReferenceProperty(
        'substation',
        _config.substationId,
        kind: ReferenceKind.substation,
      ),
    );
  }

  @override
  Seed build(TreeContext context) {
    // The ServiceBundle is a fixed-at-mount handle: the same instance is
    // re-provided on every config tick, and genesis's default identity check
    // (`value != oldSeed.value`) declines to notify — no guard type needed
    // (ADR-0008 D-6, superseded 2026-07-02).
    return InheritedSeed<ServiceBundle>(
      value: seed.services,
      child: InheritedSeed<SubstationConfig>(
        value: _config,
        child: Substation(key: ValueKey('substation.${_config.substationId}')),
      ),
    );
  }
}
