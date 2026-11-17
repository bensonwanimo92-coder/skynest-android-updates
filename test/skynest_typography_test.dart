import 'package:chuka/theme/skynest_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
    group('SkyNest ${brightness.name} typography', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF2463A6),
        brightness: brightness,
      );
      final textTheme = buildSkyNestTextTheme(scheme);

      test('provides a clear descending type hierarchy', () {
        expect(textTheme.displayLarge!.fontSize, greaterThan(textTheme.headlineLarge!.fontSize!));
        expect(textTheme.headlineLarge!.fontSize, greaterThan(textTheme.titleLarge!.fontSize!));
        expect(textTheme.titleLarge!.fontSize, greaterThan(textTheme.bodyLarge!.fontSize!));
        expect(textTheme.bodyLarge!.fontSize, greaterThan(textTheme.bodyMedium!.fontSize!));
        expect(textTheme.bodyMedium!.fontSize, greaterThan(textTheme.bodySmall!.fontSize!));
      });

      test('keeps body and compact label sizes readable', () {
        expect(textTheme.bodyLarge!.fontSize, greaterThanOrEqualTo(16));
        expect(textTheme.bodyMedium!.fontSize, greaterThanOrEqualTo(14));
        expect(textTheme.bodySmall!.fontSize, greaterThanOrEqualTo(12));
        expect(textTheme.labelSmall!.fontSize, greaterThanOrEqualTo(11));
        expect(textTheme.bodyLarge!.height, greaterThanOrEqualTo(1.45));
        expect(textTheme.bodyMedium!.height, greaterThanOrEqualTo(1.4));
      });

      test('uses theme-aware foreground colors in light and dark modes', () {
        expect(textTheme.titleLarge!.color, scheme.onSurface);
        expect(textTheme.bodyLarge!.color, scheme.onSurface);
        expect(textTheme.bodyMedium!.color, scheme.onSurface);
        expect(textTheme.bodySmall!.color, scheme.onSurfaceVariant);
        expect(textTheme.labelSmall!.color, scheme.onSurfaceVariant);
      });
    });
  }
}
