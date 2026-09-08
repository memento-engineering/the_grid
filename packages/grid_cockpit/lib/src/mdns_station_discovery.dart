import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:zero_conf_grid_assets/zero_conf_grid_assets.dart';

part 'mdns_station_discovery.freezed.dart';

/// A browsed station and its optional operator-facing control door.
@freezed
abstract class StationChoice with _$StationChoice {
  const StationChoice._();

  /// Creates a station choice.
  const factory StationChoice({
    /// The advertised station identifier.
    required String station,

    /// The normalized control-door `host:port`, or null when unavailable.
    required String? controlDoor,
  }) = _StationChoice;

  /// Maps an advertisement to the endpoint-only cockpit projection.
  factory StationChoice.fromAd(StationAd ad) {
    final door = ad.controlDoor?.trim();
    return StationChoice(
      station: ad.station,
      controlDoor: door == null || door.isEmpty ? null : door,
    );
  }

  /// Whether this station advertises a usable control-door authority.
  bool get isConnectable => controlDoor != null;
}

/// Adapts station advertisements into accumulated cockpit choices.
final class MdnsStationDiscovery {
  /// Creates discovery backed by the injected [browser].
  const MdnsStationDiscovery({required MdnsBrowser browser})
    : _browser = browser;

  final MdnsBrowser _browser;

  /// Browses once and emits a fresh immutable snapshot after every arrival.
  Stream<List<StationChoice>> browse({
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    final choices = <StationChoice>[];
    await for (final ad in _browser.browse(timeout: timeout)) {
      choices.add(StationChoice.fromAd(ad));
      yield List<StationChoice>.unmodifiable(choices);
    }
  }
}

/// Creates local-network discovery using the published multicast browser.
MdnsStationDiscovery localNetworkStationDiscovery() =>
    MdnsStationDiscovery(browser: MulticastDnsBrowser());
