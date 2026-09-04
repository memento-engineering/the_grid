import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('grid_sdk exports mergeable ledger metric totals', () {
    const cacheTokens = CacheTokenTotals(
      cacheRead: 3,
      cacheCreate: 2,
      uncachedInput: 5,
    );
    const landedDeliveries = LandedDeliveryTotals(
      landedCost: 12.5,
      landedCount: 2,
    );

    expect(
      (
        cacheTokens.cacheRead,
        cacheTokens.cacheCreate,
        cacheTokens.uncachedInput,
        landedDeliveries.landedCost,
        landedDeliveries.landedCount,
      ),
      (3, 2, 5, 12.5, 2),
    );
  });
}
