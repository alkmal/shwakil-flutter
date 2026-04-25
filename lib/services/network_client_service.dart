import 'package:http/http.dart' as http;

class NetworkClientService {
  NetworkClientService._();

  static final http.Client client = http.Client();
}
