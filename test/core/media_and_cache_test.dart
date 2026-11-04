import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/features/fleet/models/fleet_vehicle.dart';
import 'package:customer_app/features/fleet/providers/vehicle_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// Image URL resolution and the vehicle cache.
///
/// Both exist to fix a loading failure rather than to add a feature, so the
/// cases here are the ones that were actually broken: a photo URL naming a host
/// the device cannot route to, and a details screen refetching something it had
/// already loaded.
void main() {
  group('AppConfig.apiOrigin', () {
    test('is the API base with the /api prefix stripped', () {
      // The default base in a build with no --dart-define.
      expect(AppConfig.apiBaseUrl, 'http://10.0.2.2:5000/api/v1');
      expect(AppConfig.apiOrigin, 'http://10.0.2.2:5000');
    });

    test('is what the socket connects to', () {
      expect(AppConfig.socketUrl, AppConfig.apiOrigin);
    });
  });

  group('AppConfig.resolveMediaUrl', () {
    test('resolves a root-relative path against the API origin', () {
      // The shape the backend now stores for a locally served photo.
      expect(
        AppConfig.resolveMediaUrl('/uploads/vehicles/ab12.jpg'),
        'http://10.0.2.2:5000/uploads/vehicles/ab12.jpg',
      );
    });

    test('resolves a path with no leading slash too', () {
      expect(
        AppConfig.resolveMediaUrl('uploads/vehicles/ab12.jpg'),
        'http://10.0.2.2:5000/uploads/vehicles/ab12.jpg',
      );
    });

    test('rehosts a localhost URL, which no device can reach', () {
      // This is the bug. An admin uploading at localhost:5000 wrote that host
      // into MongoDB; on a phone `localhost` is the phone, so the photo request
      // went nowhere and hung until it timed out.
      expect(
        AppConfig.resolveMediaUrl('http://localhost:5000/uploads/vehicles/ab12.jpg'),
        'http://10.0.2.2:5000/uploads/vehicles/ab12.jpg',
      );
    });

    test('rehosts 127.0.0.1 and the emulator alias as well', () {
      for (final host in ['127.0.0.1', '0.0.0.0', '10.0.2.2']) {
        expect(
          AppConfig.resolveMediaUrl('http://$host:5000/uploads/x.jpg'),
          'http://10.0.2.2:5000/uploads/x.jpg',
          reason: '$host must be rehosted onto the configured API origin',
        );
      }
    });

    test('keeps the query string when rehosting', () {
      expect(
        AppConfig.resolveMediaUrl('http://localhost:5000/uploads/x.jpg?v=2'),
        'http://10.0.2.2:5000/uploads/x.jpg?v=2',
      );
    });

    test('leaves a real remote URL alone', () {
      // Cloudinary, S3, a CDN: already correct, and rewriting it would break it.
      const cloudinary =
          'https://res.cloudinary.com/demo/image/upload/v1/travels/vehicles/x.jpg';
      expect(AppConfig.resolveMediaUrl(cloudinary), cloudinary);

      const lan = 'http://192.168.1.20:5000/uploads/x.jpg';
      expect(AppConfig.resolveMediaUrl(lan), lan);
    });

    test('returns null for nothing, so a caller can show a placeholder', () {
      expect(AppConfig.resolveMediaUrl(null), isNull);
      expect(AppConfig.resolveMediaUrl(''), isNull);
      expect(AppConfig.resolveMediaUrl('   '), isNull);
    });

    test('is idempotent', () {
      final once = AppConfig.resolveMediaUrl('/uploads/x.jpg')!;
      expect(AppConfig.resolveMediaUrl(once), once);
    });
  });

  group('network budget', () {
    test('a failed read gives up in well under a minute', () {
      // The arithmetic that matters: every timeout is multiplied by the retry
      // count, and this product is how long a customer stares at a spinner
      // before being told anything. The old 20s x 3 was about 65 seconds.
      final worstCase = AppConfig.receiveTimeout * AppConfig.networkAttempts;
      expect(worstCase.inSeconds, lessThanOrEqualTo(25));
      expect(AppConfig.networkAttempts, greaterThanOrEqualTo(2),
          reason: 'one attempt leaves no tolerance for a genuine blip');
    });
  });

  group('VehicleCache', () {
    FleetVehicle vehicle(String id, {String name = 'Swift Dzire'}) => FleetVehicle(
          id: id,
          name: name,
          brand: 'Maruti',
          model: 'Dzire',
          year: 2022,
          category: 'car',
          seatingCapacity: 5,
          fuelType: 'petrol',
          transmission: 'manual',
          pricePerDay: 2000,
        );

    test('hands back what was put in', () {
      final cache = VehicleCache();
      cache.put(vehicle('v1'));

      expect(cache['v1']?.name, 'Swift Dzire');
      expect(cache['missing'], isNull);
    });

    test('takes a whole page in one state change', () {
      final cache = VehicleCache();
      var notifications = 0;
      cache.addListener((_) => notifications += 1, fireImmediately: false);

      cache.putAll([vehicle('v1'), vehicle('v2'), vehicle('v3')]);

      expect(cache.state, hasLength(3));
      // One write for the page, not one per vehicle: a list of twenty must not
      // rebuild every listener twenty times.
      expect(notifications, 1);
    });

    test('a re-put replaces the entry rather than duplicating it', () {
      final cache = VehicleCache();
      cache.put(vehicle('v1', name: 'Old name'));
      cache.put(vehicle('v1', name: 'New name'));

      expect(cache.state, hasLength(1));
      expect(cache['v1']?.name, 'New name');
    });

    test('ignores an empty id rather than caching an unreachable entry', () {
      final cache = VehicleCache();
      cache.put(vehicle(''));

      expect(cache.state, isEmpty);
    });

    test('does nothing for an empty list', () {
      final cache = VehicleCache();
      var notifications = 0;
      cache.addListener((_) => notifications += 1, fireImmediately: false);

      cache.putAll(const []);

      expect(notifications, 0);
    });

    test('evicts the oldest once it is full', () {
      final cache = VehicleCache();
      cache.putAll([
        for (var i = 0; i < VehicleCache.maxEntries + 5; i++) vehicle('v$i'),
      ]);

      expect(cache.state, hasLength(VehicleCache.maxEntries));
      // The first five written are gone; the most recent survive, which is the
      // right order - the one just tapped is the one about to be needed.
      expect(cache['v0'], isNull);
      expect(cache['v4'], isNull);
      expect(cache['v5'], isNotNull);
      expect(cache['v${VehicleCache.maxEntries + 4}'], isNotNull);
    });

    test('a re-put refreshes an entry position, so it is not evicted next', () {
      final cache = VehicleCache();
      cache.putAll([for (var i = 0; i < VehicleCache.maxEntries; i++) vehicle('v$i')]);

      // Touch the oldest, then overflow by one.
      cache.put(vehicle('v0', name: 'Touched'));
      cache.put(vehicle('fresh'));

      expect(cache['v0']?.name, 'Touched');
      // v1 was the oldest after v0 was touched, so v1 goes instead.
      expect(cache['v1'], isNull);
    });
  });
}
