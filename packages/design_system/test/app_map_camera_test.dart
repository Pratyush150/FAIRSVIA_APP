import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

/// The rider's live-tracking camera rules, tested as pure functions so they
/// don't need a live Google Maps controller.
void main() {
  // A 1x1 degree viewport. With the default 0.28 margin the quiet middle band
  // is 0.28..0.72 on both axes.
  const sw = LatLng(0, 0);
  const ne = LatLng(1, 1);

  group('needsEdgePan', () {
    test('leaves the camera alone while the car sits in the middle band', () {
      expect(AppMap.needsEdgePan(const LatLng(0.5, 0.5), sw, ne), isFalse);
      expect(AppMap.needsEdgePan(const LatLng(0.3, 0.7), sw, ne), isFalse);
      expect(AppMap.needsEdgePan(const LatLng(0.71, 0.29), sw, ne), isFalse);
    });

    test('pans once the car crosses into a margin, on either axis', () {
      // Past the top edge.
      expect(AppMap.needsEdgePan(const LatLng(0.9, 0.5), sw, ne), isTrue);
      // Past the bottom edge.
      expect(AppMap.needsEdgePan(const LatLng(0.1, 0.5), sw, ne), isTrue);
      // Comfortable north/south, but hard against the right edge — the case
      // that used to let the car drive off screen unnoticed.
      expect(AppMap.needsEdgePan(const LatLng(0.5, 0.95), sw, ne), isTrue);
      expect(AppMap.needsEdgePan(const LatLng(0.5, 0.05), sw, ne), isTrue);
    });

    test('pans when the car is already outside the viewport entirely', () {
      expect(AppMap.needsEdgePan(const LatLng(2, 2), sw, ne), isTrue);
      expect(AppMap.needsEdgePan(const LatLng(-1, 0.5), sw, ne), isTrue);
    });

    test('holds still when the viewport is not measurable', () {
      // Zero span (controller not laid out yet) and an inverted box (a view
      // straddling the antimeridian) both mean "nothing to compare against".
      expect(AppMap.needsEdgePan(const LatLng(0.5, 0.5), sw, sw), isFalse);
      expect(
        AppMap.needsEdgePan(const LatLng(0.5, 0.5), ne, sw),
        isFalse,
      );
    });

    test('a wider margin makes the camera more eager to follow', () {
      const car = LatLng(0.8, 0.5);
      expect(AppMap.needsEdgePan(car, sw, ne, margin: 0.05), isFalse);
      expect(AppMap.needsEdgePan(car, sw, ne, margin: 0.28), isTrue);
    });
  });

  group('lookAhead', () {
    test('aims past the car in its direction of travel', () {
      // Heading due north from the middle of the viewport.
      final aimed = AppMap.lookAhead(const LatLng(0.5, 0.5), 0, sw, ne);
      expect(aimed.latitude, greaterThan(0.5)); // moved north
      expect(aimed.longitude, closeTo(0.5, 1e-9)); // not sideways
      // Due east.
      final east = AppMap.lookAhead(const LatLng(0.5, 0.5), 90, sw, ne);
      expect(east.longitude, greaterThan(0.5));
      expect(east.latitude, closeTo(0.5, 1e-9));
    });

    test('the lead stays inside the viewport', () {
      // A full half-span would put the aim point on the edge; the default
      // fraction must keep it comfortably short of that.
      final aimed = AppMap.lookAhead(const LatLng(0.5, 0.5), 0, sw, ne);
      expect(aimed.latitude - 0.5, lessThan(0.5));
      expect(aimed.latitude - 0.5, closeTo(0.5 * AppMap.lookAheadFraction, 1e-9));
    });

    test('a bigger fraction leads further ahead', () {
      final near = AppMap.lookAhead(const LatLng(0.5, 0.5), 0, sw, ne,
          fraction: 0.1);
      final far = AppMap.lookAhead(const LatLng(0.5, 0.5), 0, sw, ne,
          fraction: 0.4);
      expect(far.latitude, greaterThan(near.latitude));
    });

    test('an unknown heading leads nowhere', () {
      // Leading in a direction we are only guessing at is worse than centring.
      const car = LatLng(0.5, 0.5);
      expect(AppMap.lookAhead(car, null, sw, ne), car);
    });

    test('an unmeasurable viewport leads nowhere', () {
      const car = LatLng(0.5, 0.5);
      expect(AppMap.lookAhead(car, 45, sw, sw), car);
      expect(AppMap.lookAhead(car, 45, ne, sw), car);
    });

    test('south-west travel leads south and west', () {
      final aimed = AppMap.lookAhead(const LatLng(0.5, 0.5), 225, sw, ne);
      expect(aimed.latitude, lessThan(0.5));
      expect(aimed.longitude, lessThan(0.5));
    });
  });

  group('isUserGesture', () {
    test('a deliberate drag takes the camera', () {
      expect(AppMap.isUserGesture(200, false), isTrue);
    });

    test('a deliberate zoom takes the camera too', () {
      // The spec is "if the user pans, drags OR zooms, pause following".
      // Measuring only the drag made the outcome depend on HOW the user
      // zoomed: a centred pinch barely moves the centre and survived, while an
      // off-centre double-tap shifted it and suspended following. Same intent,
      // two different results — worse than either rule applied consistently.
      expect(AppMap.isUserGesture(0, true), isTrue);
    });

    test('a nudge that is neither leaves the camera following', () {
      // Sub-threshold drift during an animation must not look like the rider
      // grabbing the map.
      expect(AppMap.isUserGesture(5, false), isFalse);
      expect(AppMap.isUserGesture(AppMap.panThresholdMeters, false), isFalse);
    });

    test('an unmeasurable gesture is treated as the user taking over', () {
      // No end position to compare against: yielding the camera is the safe
      // failure, because the alternative is fighting a rider who did move it.
      expect(AppMap.isUserGesture(double.infinity, false), isTrue);
    });
  });

  group('glideFor', () {
    test('stretches the glide to match the gap between fixes', () {
      expect(
        AppMap.glideFor(const Duration(milliseconds: 1200)),
        const Duration(milliseconds: 1200),
      );
    });

    test('floors a burst so the marker cannot strobe', () {
      expect(
        AppMap.glideFor(const Duration(milliseconds: 50)),
        const Duration(milliseconds: 600),
      );
      expect(AppMap.glideFor(Duration.zero),
          const Duration(milliseconds: 600));
    });

    test('caps a stalled stream so the car cannot crawl indefinitely', () {
      expect(
        AppMap.glideFor(const Duration(seconds: 30)),
        const Duration(milliseconds: 1600),
      );
    });
  });

  group('lerpBearing', () {
    test('turns the short way through north', () {
      expect(AppMap.lerpBearing(350, 10, 0.5), closeTo(0, 1e-9));
      expect(AppMap.lerpBearing(10, 350, 0.5), closeTo(0, 1e-9));
      expect(AppMap.lerpBearing(350, 10, 0.25), closeTo(355, 1e-9));
    });

    test('ends exactly on the target and starts on the source', () {
      expect(AppMap.lerpBearing(90, 200, 0), closeTo(90, 1e-9));
      expect(AppMap.lerpBearing(90, 200, 1), closeTo(200, 1e-9));
    });

    test('never sweeps more than 180 degrees', () {
      for (var a = 0.0; a < 360; a += 23) {
        for (var b = 0.0; b < 360; b += 31) {
          final mid = AppMap.lerpBearing(a, b, 0.5);
          final half = ((mid - a + 540) % 360 - 180).abs();
          expect(half, lessThanOrEqualTo(90 + 1e-9));
        }
      }
    });
  });

  group('turnProgress', () {
    test('eases from 0, finishes early in the glide and holds', () {
      expect(AppMap.turnProgress(0), 0);
      expect(AppMap.turnProgress(AppMap.turnShare), closeTo(1, 1e-9));
      expect(AppMap.turnProgress(1), 1);
      // Gentle start: slower than linear at first.
      expect(AppMap.turnProgress(0.06), lessThan(0.1));
    });
  });

  group('screenPoint with map padding (radar anchoring)', () {
    const size = Size(400, 800);
    final target = const LatLng(18.52, 73.86);
    final pickup = const LatLng(18.515, 73.855);

    test('a taller bottom padding lifts the target by half the difference', () {
      final tall = AppMap.screenPoint(target, target, 15, size,
          const EdgeInsets.fromLTRB(0, 96, 0, 500));
      final short = AppMap.screenPoint(target, target, 15, size,
          const EdgeInsets.fromLTRB(0, 96, 0, 200));
      expect(short.dy - tall.dy, closeTo(150, 1e-9));
      expect(short.dx, tall.dx);
    });

    test('an off-centre point keeps its offset from the padded centre', () {
      const pad = EdgeInsets.fromLTRB(40, 96, 40, 420);
      final c = AppMap.screenPoint(target, target, 15, size, pad);
      final p = AppMap.screenPoint(pickup, target, 15, size, pad);
      final p0 = AppMap.screenPoint(pickup, target, 15, size, EdgeInsets.zero);
      final c0 = AppMap.screenPoint(target, target, 15, size, EdgeInsets.zero);
      expect(p - c, offsetMoreOrLessEquals(p0 - c0));
      // Padded centre: (40 + 320/2, 96 + 284/2).
      expect(c, const Offset(200, 238));
    });

    test('a stale camera after a padding change is exactly what the '
        'correction carries', () {
      // The native map re-centred on the new padded area without reporting a
      // camera move: the overlay still projects with the new padding but the
      // old target. The measured correction puts the rings back on the pin.
      const before = EdgeInsets.fromLTRB(40, 96, 40, 560);
      const after = EdgeInsets.fromLTRB(40, 96, 40, 180);
      final drawnAt = AppMap.screenPoint(pickup, target, 15, size, before);
      final predicted = AppMap.screenPoint(pickup, target, 15, size, after);
      final fix = AppMap.pulseCorrection(predicted, drawnAt, size);
      expect(fix.dx, 0);
      expect(fix.dy, closeTo(-190, 1e-9)); // rings were 190 px too low
      expect(predicted + fix, offsetMoreOrLessEquals(drawnAt));
    });

    test('an unbelievable measurement is ignored', () {
      expect(
          AppMap.pulseCorrection(Offset.zero, const Offset(5000, 0), size),
          Offset.zero);
      expect(
          AppMap.pulseCorrection(
              Offset.zero, const Offset(double.nan, 0), size),
          Offset.zero);
    });

    test('Android screen coordinates are physical pixels; others logical', () {
      expect(AppMap.nativeToLogical(const Offset(300, 600), 3, android: true),
          const Offset(100, 200));
      expect(AppMap.nativeToLogical(const Offset(300, 600), 3, android: false),
          const Offset(300, 600));
    });
  });

  group('follow camera against the uncovered map area', () {
    const size = Size(400, 800);
    const pad = EdgeInsets.fromLTRB(40, 96, 40, 420); // tall glass card

    test('a car hidden behind the sheet needs a pan', () {
      expect(AppMap.needsEdgePanOnScreen(const Offset(200, 600), size, pad),
          isTrue);
    });

    test('a car in the middle of the uncovered strip is left alone', () {
      expect(AppMap.needsEdgePanOnScreen(const Offset(200, 238), size, pad),
          isFalse);
    });

    test('a car at the left edge needs a pan', () {
      expect(AppMap.needsEdgePanOnScreen(const Offset(10, 238), size, pad),
          isTrue);
    });

    test('an unmeasurable area holds still', () {
      expect(
          AppMap.needsEdgePanOnScreen(const Offset(10, 10), size,
              const EdgeInsets.fromLTRB(0, 400, 0, 400)),
          isFalse);
    });
  });

  group('fitting the ride', () {
    test('bounds padding leaves room for the car and its plate tag', () {
      expect(AppMap.fitPaddingFor(0), 56);
      expect(AppMap.fitPaddingFor(150), greaterThanOrEqualTo(150 / 2 + 16));
    });

    test('fitZoom frames the points inside the box', () {
      final pts = [const LatLng(18.50, 73.84), const LatLng(18.53, 73.88)];
      const box = Size(300, 60);
      final z = AppMap.fitZoom(pts, box);
      final a = AppMap.screenPoint(
          pts[0], const LatLng(18.515, 73.86), z, box, EdgeInsets.zero);
      final b = AppMap.screenPoint(
          pts[1], const LatLng(18.515, 73.86), z, box, EdgeInsets.zero);
      expect((a.dx - b.dx).abs(), lessThanOrEqualTo(box.width + 1e-6));
      expect((a.dy - b.dy).abs(), lessThanOrEqualTo(box.height + 1e-6));
      // Tight on at least one axis.
      expect(
          math.max((a.dx - b.dx).abs() / box.width,
              (a.dy - b.dy).abs() / box.height),
          closeTo(1, 1e-6));
      // Half the box, one zoom level out.
      expect(AppMap.fitZoom(pts, const Size(150, 30)), closeTo(z - 1, 1e-9));
    });
  });

  group('screenPoint', () {
    const size = Size(400, 800);
    const target = LatLng(18.52, 73.85);

    test('the camera target sits at the centre of the padded area', () {
      final p = AppMap.screenPoint(target, target, 16, size,
          const EdgeInsets.fromLTRB(40, 96, 40, 300));
      expect(p.dx, closeTo(200, 1e-6));
      expect(p.dy, closeTo(96 + (800 - 396) / 2, 1e-6));
    });

    test('north is up and east is right', () {
      final north = AppMap.screenPoint(
          const LatLng(18.53, 73.85), target, 16, size, EdgeInsets.zero);
      final east = AppMap.screenPoint(
          const LatLng(18.52, 73.86), target, 16, size, EdgeInsets.zero);
      expect(north.dy, lessThan(400));
      expect(north.dx, closeTo(200, 1e-6));
      expect(east.dx, greaterThan(200));
    });

    test('distance on screen doubles with each zoom level', () {
      const p = LatLng(18.521, 73.851);
      final a = AppMap.screenPoint(p, target, 15, size, EdgeInsets.zero);
      final b = AppMap.screenPoint(p, target, 16, size, EdgeInsets.zero);
      final c = const Offset(200, 400);
      expect((b - c).distance, closeTo((a - c).distance * 2, 1e-6));
    });

    test('pixelsPerMetre agrees with the projection', () {
      // 100 m east at the equator, zoom 16.
      const eq = LatLng(0, 0);
      final px = AppMap.screenPoint(
              const LatLng(0, 100 / 111319.49), eq, 16, size, EdgeInsets.zero)
          .dx - 200;
      expect(px, closeTo(100 * AppMap.pixelsPerMetre(0, 16), 0.05));
    });
  });

  group('pickup rings stay glued to the pickup through a drag', () {
    const size = Size(400, 800);
    const pad = EdgeInsets.fromLTRB(40, 96, 40, 300);
    const pickup = LatLng(18.515, 73.855);
    const t0 = LatLng(18.515, 73.855); // camera on the pickup
    const t1 = LatLng(18.515, 73.857); // dragged: camera moved east

    test('the centre follows every camera position, by projection', () {
      final a = AppMap.ringCentre(
          at: pickup, target: t0, zoom: 15, size: size, padding: pad);
      final b = AppMap.ringCentre(
          at: pickup, target: t1, zoom: 15, size: size, padding: pad);
      expect(a, AppMap.screenPoint(pickup, t0, 15, size, pad));
      expect(b, AppMap.screenPoint(pickup, t1, 15, size, pad));
      // Camera east => the pickup slides west on screen, exactly as the map.
      expect(b.dx, lessThan(a.dx));
      expect(b.dy, closeTo(a.dy, 1e-6));
    });

    test('zoom moves and resizes the rings with the map', () {
      const off = LatLng(18.516, 73.856);
      final z15 = AppMap.ringCentre(
          at: off, target: t0, zoom: 15, size: size, padding: pad);
      final z16 = AppMap.ringCentre(
          at: off, target: t0, zoom: 16, size: size, padding: pad);
      final c = AppMap.screenPoint(t0, t0, 15, size, pad);
      expect((z16 - c).distance, closeTo(2 * (z15 - c).distance, 1e-6));
      final (_, r14) = AppMap.ringRadii(pickup.latitude, 14);
      final (_, r16) = AppMap.ringRadii(pickup.latitude, 16);
      expect(r16, greaterThan(r14));
      expect(AppMap.ringRadii(pickup.latitude, 3).$2, 56); // clamped
      expect(AppMap.ringRadii(pickup.latitude, 20).$2, 150);
    });

    test('the measured correction is added on top', () {
      final c = AppMap.ringCentre(
          at: pickup,
          target: t0,
          zoom: 15,
          size: size,
          padding: pad,
          correction: const Offset(3, -40));
      expect(c, AppMap.screenPoint(pickup, t0, 15, size, pad) +
          const Offset(3, -40));
    });

    test('between slow callbacks it is carried forward one frame by the '
        'drag velocity', () {
      final last = AppMap.screenPoint(pickup, t1, 15, size, pad);
      final prev = AppMap.screenPoint(pickup, t0, 15, size, pad);
      Offset at(int nowUs) => AppMap.ringCentre(
          at: pickup,
          target: t1,
          zoom: 15,
          prevTarget: t0,
          prevZoom: 15,
          prevUs: 0,
          lastUs: 33000, // callbacks every 33 ms (30 Hz)
          nowUs: nowUs,
          size: size,
          padding: pad);
      final v = (last - prev) / 33000; // px per microsecond
      // 8 ms after the callback: 8 ms further along the drag.
      expect(at(41000), offsetMoreOrLessEquals(last + v * 8000.0));
      // Never more than one frame ahead.
      expect(at(70000),
          offsetMoreOrLessEquals(last + v * AppMap.extrapolateMaxUs.toDouble()));
      // Callbacks stopped (camera idle): no guessing, the real point.
      expect(at(33000 + AppMap.extrapolateStaleUs), last);
    });

    test('no extrapolation under Reduce Motion or without a pair', () {
      final plain = AppMap.screenPoint(pickup, t1, 15, size, pad);
      expect(
          AppMap.ringCentre(
              at: pickup,
              target: t1,
              zoom: 15,
              prevTarget: t0,
              prevZoom: 15,
              prevUs: 0,
              lastUs: 33000,
              nowUs: 41000,
              size: size,
              padding: pad,
              extrapolate: false),
          plain);
      expect(
          AppMap.ringCentre(
              at: pickup, target: t1, zoom: 15, size: size, padding: pad,
              lastUs: 33000, nowUs: 41000),
          plain);
    });

    test('every camera callback repaints the rings (no hiding on move)', () {
      final track = CameraTrack(
          const gmaps.CameraPosition(target: gmaps.LatLng(18.5, 73.8)));
      var repaints = 0;
      track.addListener(() => repaints++);
      for (var i = 0; i < 5; i++) {
        track.add(
            gmaps.CameraPosition(
                target: gmaps.LatLng(18.5, 73.8 + i * 0.001), zoom: 15),
            i * 16000);
      }
      expect(repaints, 5);
      expect(track.last.target.longitude, closeTo(73.804, 1e-9));
      expect(track.prev!.target.longitude, closeTo(73.803, 1e-9));
      expect(track.lastUs - track.prevUs, 16000);
    });
  });

  group('CalmPulse ring timing', () {
    test('a calm period, three rings evenly staggered', () {
      expect(CalmPulse.period, const Duration(milliseconds: 3400));
      expect(CalmPulse.peak, lessThanOrEqualTo(0.4));
      final r = CalmPulse.all(0.4);
      expect(r, hasLength(3));
      expect(CalmPulse.ring(0.4, 1), CalmPulse.ring(0.4 + 1 / 3, 0));
    });

    test('a ring is invisible at both ends, so the loop never pops', () {
      expect(CalmPulse.ring(0, 0).$2, 0);
      expect(CalmPulse.ring(0.9999, 0).$2, lessThan(0.001));
      // Continuous across the wrap: the ring leaving and the one arriving
      // are both (nearly) transparent.
      final before = CalmPulse.ring(0.999, 0).$2;
      final after = CalmPulse.ring(0.001, 0).$2;
      expect((before - after).abs(), lessThan(0.01));
    });

    test('opacity never exceeds the soft peak', () {
      for (var t = 0.0; t < 1; t += 0.01) {
        for (final (spread, o) in CalmPulse.all(t)) {
          expect(o, inInclusiveRange(0, CalmPulse.peak));
          expect(spread, inInclusiveRange(0, 1));
        }
      }
    });

    test('spread eases out: quick off the pin, settling at the edge', () {
      final early = CalmPulse.ring(0.1, 0).$1; // 10% of the time
      expect(early, greaterThan(0.2));
      final late = CalmPulse.ring(0.9, 0).$1 - CalmPulse.ring(0.8, 0).$1;
      expect(late, lessThan(0.05));
    });

    test('grows monotonically through its life', () {
      var last = -1.0;
      for (var t = 0.0; t < 1; t += 0.02) {
        final s = CalmPulse.ring(t, 0).$1;
        expect(s, greaterThanOrEqualTo(last));
        last = s;
      }
    });
  });
}
