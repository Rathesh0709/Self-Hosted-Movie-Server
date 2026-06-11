import 'package:flutter_test/flutter_test.dart';
import 'package:streamflix/core/utils/formatters.dart';

void main() {
  test('formatRuntime formats minutes', () {
    expect(formatRuntime(134), '2h 14m');
    expect(formatRuntime(47), '47m');
    expect(formatRuntime(0), '');
  });

  test('generateWatchId composes id', () {
    expect(generateWatchId('movie', 42), 'movie-42');
  });
}
