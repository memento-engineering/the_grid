/// DevTools extension for the_grid.
///
/// Attaches to a running grid process over the exploration protocol only
/// (ADR-0002 Decision 3) — never imports beads_dart directly. The
/// protocol-call layer ([GridExplorationClient]) is kept thin and separate
/// from the widgets so the panels are unit-testable against a fake client
/// with no live VM service.
library;

export 'src/events/events_panel.dart' show EventsPanel;
export 'src/events/events_source.dart' show GridEventsSource;
export 'src/grid_devtools_shell.dart' show GridDevToolsShell;
export 'src/handshake_state.dart'
    show
        HandshakeBindingMissing,
        HandshakeFailed,
        HandshakeLoaded,
        HandshakeLoading,
        HandshakeState;
export 'src/protocol/grid_exploration_client.dart'
    show
        GridBindingMissing,
        GridEventRecord,
        GridEventsPage,
        GridExplorationClient,
        GridHandshake,
        GridPlugin,
        kEventsExtension,
        kGridEventStreamId,
        kHandshakeExtension;
export 'src/protocol/vm_service_grid_client.dart' show VmServiceGridClient;

const String packageName = 'grid_devtools';
