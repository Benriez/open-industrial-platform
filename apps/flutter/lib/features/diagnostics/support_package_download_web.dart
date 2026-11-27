import '../../services/local_text_download_web.dart';

void downloadSupportPackage(String json) {
  downloadLocalText('oip-support.json', json, 'application/json;charset=utf-8');
}
