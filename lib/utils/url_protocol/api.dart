// Android-only: URL protocol registration is not needed on Android.
// These are no-op stubs to avoid breaking any imports that remained.

void registerProtocolHandler(
  String scheme, {
  String? executable,
  List<String>? arguments,
}) {
  // No-op on Android
}

void unregisterProtocolHandler(String scheme) {
  // No-op on Android
}
