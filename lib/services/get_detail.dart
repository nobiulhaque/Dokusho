import 'dart:async';
import 'package:dokusho/eval/model/m_manga.dart';
import 'package:dokusho/models/source.dart';
import 'package:dokusho/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:dokusho/services/isolate_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'get_detail.g.dart';

@riverpod
Future<MManga> getDetail(
  Ref ref, {
  required String url,
  required Source source,
}) async {
  final proxyServer = ref.read(androidProxyServerStateProvider);

  return getIsolateService.get<MManga>(
    url: url,
    source: source,
    serviceType: 'getDetail',
    proxyServer: proxyServer,
  );
}
