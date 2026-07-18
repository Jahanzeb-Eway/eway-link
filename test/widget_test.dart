import 'package:eway_link/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EWAY LINK application', () {
    test('root application can be constructed', () {
      const app = EwayLinkApp();

      expect(app, isA<StatelessWidget>());
      expect(app.key, isNull);
    });
  });
}
