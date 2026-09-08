# grid_station_client

Web-safe client composition for the resident grid station.

`StationLockDiscovery` decodes the first usable `.grid/station.lock` from
injected workspace-root and text-file adapters. The package performs no file
I/O itself, so browser consumers can supply DTD adapters while desktop clients
can supply local-file adapters.

`LiveConnectionController` owns the shared discovery/manual-connection state
machine and the connected `TreeSource`. `WebSocketTreeWireSource` receives
`TreeSnapshot` JSON from the authenticated StationControl `/stream` door.
