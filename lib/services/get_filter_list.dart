import 'package:dokusho/eval/lib.dart';
import 'package:dokusho/models/source.dart';

List<dynamic> getFilterList({required Source source}) {
  final service = getExtensionService(source, "");
  try {
    return service.getFilterList().filters;
  } finally {
    service.dispose();
  }
}
