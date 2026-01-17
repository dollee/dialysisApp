import 'package:http/http.dart' as http;

class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._headers, {http.Client? inner})
      : _inner = inner ?? http.Client();

  final Map<String, String> _headers;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
