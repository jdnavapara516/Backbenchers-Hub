import 'package:flutter_test/flutter_test.dart';

import 'package:lecturepass/main.dart';

void main() {
  testWidgets('App shows login page', (WidgetTester tester) async {
    await tester.pumpWidget(const BingoApp());
    expect(find.text('Login'), findsWidgets);
  });
}
