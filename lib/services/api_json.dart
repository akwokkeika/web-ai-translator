import 'dart:convert';

Map<String, dynamic> decodeJsonMap(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {'raw': decoded};
  } on FormatException {
    return {'error': body};
  }
}

String? jsonErrorMessage(Map<String, dynamic> json) {
  final error = json['error'];
  if (error is Map && error['message'] != null) {
    return error['message'].toString();
  }
  if (error is String && error.trim().isNotEmpty) return error;
  return null;
}
