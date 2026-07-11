class InquiryNumberGenerator {
  static int _counter = 1;

  static String generate() {
    final now = DateTime.now();

    final yy = now.year.toString().substring(2);
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');

    final number = _counter.toString().padLeft(4, '0');

    _counter++;

    return "INQ-$yy$mm$dd-$number";
  }
}