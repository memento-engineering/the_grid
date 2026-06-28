import 'package:genesis_tree/genesis_tree.dart';
import 'package:state_notifier/state_notifier.dart';

import '../domain/substation_config.dart';
import '../formula/stable_inherited.dart';
import '../notifiers/substation_config_notifier.dart';
import '../sdk/capability.dart';
import 'substation.dart';

/// The per-rig **config scope** — an ancestor of the rig's work nodes
/// (ADR-0007: config nodes are ancestors of work nodes).
///
/// It OBSERVES the rig's [SubstationConfigNotifier] (the config axis, separate from
/// the work/snapshot axis) and re-provides the current [SubstationConfig] ambiently
/// via `InheritedSeed<SubstationConfig>` to the work subtree below it.
///
/// It is ALSO where the substation's [ServiceBundle] is provided (ADR-0008 D5:
/// source control is a SUBSTATION responsibility — a project dictates its own
/// SCM; the station only supplies shared git-execution machinery the substation
/// leases). The bundle is re-provided via a [StableInheritedSeed] (D-6:
/// `updateShouldNotify => false` — it is a long-lived handle, never an in-place
/// swap), scoped to THIS substation's subtree: a `CapabilityHost` deep below
/// resolves the NEAREST bundle, so each substation's work runs against its own
/// source control, never a station-wide one. Provided here rather than above
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
class SubstationScope extends StatefulSeed {
  /// Creates a scope driven by [configNotifier], providing [services] to its
  /// subtree. Key it by rig id at the Station level so a rig add/remove
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

class _SubstationScopeState extends State<SubstationScope> {
  RemoveListener? _remove;
  late SubstationConfig _config;

  @override
  void initState() {
    _config = seed.configNotifier.current;
    _remove = seed.configNotifier.addListener(
      (config) => setState(() => _config = config),
      fireImmediately: false,
    );
  }

  @override
  void dispose() {
    _remove?.call();
    _remove = null;
  }

  @override
  Seed build(TreeContext context) {
    // The ServiceBundle is a STABLE handle (D-6): re-providing it on a config
    // tick must NOT notify dependents (a CapabilityHost resolving it must not
    // fan-rebuild), so it rides StableInheritedSeed, not a plain InheritedSeed.
    return StableInheritedSeed<ServiceBundle>(
      value: seed.services,
      child: InheritedSeed<SubstationConfig>(
        value: _config,
        child: Substation(key: ValueKey('substation.${_config.substationId}')),
      ),
    );
  }
}
