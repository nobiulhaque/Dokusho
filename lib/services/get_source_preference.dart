import 'package:dokusho/eval/lib.dart';
import 'package:dokusho/eval/model/source_preference.dart';
import 'package:dokusho/models/source.dart';

List<SourcePreference> getSourcePreference({required Source source}) {
  final service = getExtensionService(source, "");
  try {
    return service.getSourcePreferences();
  } finally {
    service.dispose();
  }
}
