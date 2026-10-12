import 'package:flutter_test/flutter_test.dart';

import 'package:p2p_vois/crypto/payload_cipher.dart';

void main() {
  test('encrypt/decrypt round-trips arbitrary text', () {
    final cipher = PayloadCipher(PayloadCipher.generateKey());
    const plaintext = '{"text":"मदद चाहिए","lang":"hi","sentAt":123}';
    final ciphertext = cipher.encrypt(plaintext);
    expect(cipher.decrypt(ciphertext), plaintext);
  });

  test('two random keys are different and cross-decryption fails', () {
    final a = PayloadCipher(PayloadCipher.generateKey());
    final b = PayloadCipher(PayloadCipher.generateKey());
    final ciphertext = a.encrypt('hello');
    expect(() => b.decrypt(ciphertext), throwsA(anything));
  });

  test('broadcast cipher key is stable across calls (same wire format)', () {
    final c1 = PayloadCipher.broadcast;
    final c2 = PayloadCipher.broadcast;
    final ciphertext = c1.encrypt('SOS');
    expect(c2.decrypt(ciphertext), 'SOS');
  });

  test('ciphertext differs each call due to random IV', () {
    final cipher = PayloadCipher(PayloadCipher.generateKey());
    final a = cipher.encrypt('same text');
    final b = cipher.encrypt('same text');
    expect(a, isNot(equals(b)));
    expect(cipher.decrypt(a), 'same text');
    expect(cipher.decrypt(b), 'same text');
  });
}
