import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/karmopath_app.dart';

void main() {
  testWidgets('foundation renders without fake listings', (tester) async {
    await tester.pumpWidget(const KarmopathApp());
    expect(find.text('Karmopath · কর্মপথ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
