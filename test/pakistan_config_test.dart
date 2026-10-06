import 'package:flutter_test/flutter_test.dart';
import 'package:foododer/config/pakistan_config.dart';

void main() {
  test('Pakistan configuration uses PKR and +92 defaults', () {
    expect(PakistanConfig.currencyCode, 'PKR');
    expect(PakistanConfig.countryDialCode, '+92');
  });
}
