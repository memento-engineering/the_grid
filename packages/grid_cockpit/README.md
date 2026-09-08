# grid_cockpit

Watch-only macOS operator client for a resident grid station. The cockpit
renders the station's live `TreeSnapshot` stream without requiring DevTools or
a VM service.

## On-box connection

Launch from the grid home that contains `.grid/station.lock`:

```sh
flutter run -d macos --project-root packages/grid_cockpit
```

The app reads that lock once at startup and connects to its StationControl URL
with the per-boot token.

## Manual connection

If local discovery is unavailable, enter the station `host:port` (or an
absolute HTTP(S) control URL with an explicit port) and copy the per-boot token
from the station lock. Both paths connect to the authenticated `/stream` door.
