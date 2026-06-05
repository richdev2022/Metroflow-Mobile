import 'dart:convert';

void main() {
  const String token = 'eyJ1c2VySWQiOiI3NTZmMTJiMi01OTY5LTRlYWUtOGFhOC1lNGNjNzczY2Y4MjQiLCJidXNpbmVzc0lkIjoiVkJSSEEzOSIsImlhdCI6MTc4MDU2ODQ2MiwiZXhwIjoxNzgwNjU0ODYyfQ==';
  final parts = token.split('.');
  if (parts.length != 3) {
    print('Invalid token');
    return;
  }

  // Decode payload (part 1)
  final payload = base64Url.decode(base64.normalize(parts[1]));
  print('=== Decoded Token Payload ===');
  print(utf8.decode(payload));
}
// ignore_for_file: avoid_print
