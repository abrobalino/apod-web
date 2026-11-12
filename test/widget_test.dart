import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apod/main.dart';

void main() {
  testWidgets('Apod app smoke test with calendar action', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MyApp), findsOneWidget);
    expect(find.text('Foto Astronómica'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
  });

  group('Apod.fromJson video extraction', () {
    test('extracts direct MP4 source and keeps hdurl thumbnail', () {
      final apod = Apod.fromJson({
        'date': '2026-10-28',
        'title': 'Mutual Occultation',
        'media_type': 'video',
        'url': 'https://science.nasa.gov/image-article/example/',
        'hdurl': 'https://assets.science.nasa.gov/occultation.jpeg',
        'basic_html': '<video controls><source src="https://assets.science.nasa.gov/occultation.mp4" type="video/mp4"></video>',
        'explanation': '<p>Test explanation</p>',
      });

      expect(apod.mediaType, 'video');
      expect(apod.videoUrl, 'https://assets.science.nasa.gov/occultation.mp4');
      expect(apod.url, 'https://assets.science.nasa.gov/occultation.jpeg');
      expect(apod.explanation, 'Test explanation');
    });

    test('normalizes YouTube embed iframe and derives thumbnail fallback', () {
      final apod = Apod.fromJson({
        'date': '2026-10-18',
        'title': 'Sonified Pillars',
        'media_type': 'video',
        'url': 'https://www.youtube.com/embed/DzrCEm1ZBRY?rel=0',
        'basic_html': '<iframe src="//www.youtube.com/embed/DzrCEm1ZBRY?rel=0"></iframe>',
        'explanation': 'Clean text',
      });

      expect(apod.videoUrl, 'https://www.youtube.com/watch?v=DzrCEm1ZBRY');
      expect(apod.url, 'https://img.youtube.com/vi/DzrCEm1ZBRY/hqdefault.jpg');
    });
  });
}
