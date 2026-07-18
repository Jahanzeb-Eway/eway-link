import 'package:geocoding/geocoding.dart';

class LocationAddressService {
  LocationAddressService._();

  static final LocationAddressService instance = LocationAddressService._();

  Future<String> resolve({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return 'Location name unavailable';

      final place = placemarks.first;
      final parts = <String>[
        _clean(place.name),
        _clean(place.street),
        _clean(place.subLocality),
        _clean(place.locality),
        _clean(place.administrativeArea),
        _clean(place.country),
      ].where((part) => part.isNotEmpty).toList();

      final uniqueParts = <String>[];
      for (final part in parts) {
        final alreadyIncluded = uniqueParts.any(
          (existing) => existing.toLowerCase() == part.toLowerCase(),
        );
        if (!alreadyIncluded) uniqueParts.add(part);
      }

      return uniqueParts.isEmpty
          ? 'Location name unavailable'
          : uniqueParts.join(', ');
    } catch (_) {
      return 'Location name unavailable';
    }
  }

  String _clean(String? value) {
    final cleaned = value?.trim() ?? '';
    if (cleaned.toLowerCase() == 'unnamed road') return '';
    return cleaned;
  }
}
