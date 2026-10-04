import 'dart:math';

Random random = Random();

int generateRandomNumber() {
  return random.nextInt(10000000);
}

extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}