import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/shared/format.dart';

void main() {
  test('relative times read naturally', () {
    final now = DateTime(2026, 10, 13, 12);
    expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
    expect(timeAgo(now.subtract(const Duration(days: 1)), now: now), 'yesterday');
    expect(timeAgo(now.subtract(const Duration(days: 4)), now: now), '4 days ago');
    expect(timeAgo(DateTime(2025, 3, 9), now: now), '9 Mar 2025');
  });

  test('home-relative paths', () {
    expect(shortPath('/root'), '~');
    expect(shortPath('/root/projects/app'), '~/projects/app');
    expect(shortPath('/rootless'), '/rootless');
    expect(shortPath('/srv/x'), '/srv/x');
  });

  test('counts', () {
    expect(plural(1, 'file'), '1 file');
    expect(plural(3, 'file'), '3 files');
    expect(plural(2, 'branch', 'branches'), '2 branches');
  });
}
