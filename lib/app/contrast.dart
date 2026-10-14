import 'dart:math' as math;
import 'package:flutter/painting.dart';

/// WCAG 2.x contrast ratio between two opaque colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

double _luminance(Color c) {
  double channel(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}
