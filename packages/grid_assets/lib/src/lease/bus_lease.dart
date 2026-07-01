/// The bus-backed lease handle a federation [LeaseCapability] holds — the opaque
/// `H` for the core lease family over `grid_federation`'s bus (ADR-0009 D6 / the
/// "leasing is core" decision).
///
/// The core `LeaseCapability<H>` / `LeaseAllocation<H>` name no transport; this is
/// the concrete handle the compute + burn asset capabilities acquire and carry: a
/// bus [StationClient] to the lease owner + the held [LeaseGrant] (the fencing
/// token rides every dispatch/heartbeat/release). A single-station local lease
/// would use a different handle (a local slot) — the engine never sees either.
library;

import 'package:grid_federation/grid_federation.dart';

/// A held bus lease: the bus [client] to the owner + the granted lease.
typedef BusLease = ({StationClient client, LeaseGrant grant});
