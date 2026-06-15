import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:isar_community/isar.dart';
import 'package:dokusho/eval/model/m_bridge.dart';
import 'package:dokusho/models/custom_button.dart';
import 'package:dokusho/models/manga.dart';
import 'package:dokusho/models/settings.dart';
import 'package:dokusho/models/source.dart';
import 'package:dokusho/modules/manga/reader/providers/crop_borders_provider.dart';
import 'package:dokusho/modules/more/data_and_storage/providers/storage_usage.dart';
import 'package:dokusho/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:dokusho/modules/more/settings/general/providers/general_state_provider.dart';
import 'package:dokusho/providers/l10n_providers.dart';
import 'package:dokusho/providers/storage_provider.dart';
import 'package:dokusho/router/router.dart';
import 'package:dokusho/modules/more/settings/appearance/providers/theme_mode_state_provider.dart';
import 'package:dokusho/l10n/generated/app_localizations.dart';
import 'package:dokusho/services/http/m_client.dart';
import 'package:dokusho/services/isolate_service.dart';
import 'package:dokusho/services/m_extension_server.dart';
import 'package:dokusho/services/download_manager/m_downloader.dart';
import 'package:dokusho/src/rust/frb_generated.dart';
import 'package:dokusho/utils/log/logger.dart';
import 'package:dokusho/modules/more/settings/appearance/providers/theme_provider.dart';
import 'package:dokusho/modules/library/providers/file_scanner.dart';
import 'package:dokusho/modules/more/settings/security/providers/security_state_provider.dart';
import 'package:dokusho/modules/more/settings/security/app_lock_screen.dart';

late Isar isar;
WebViewEnvironment? webViewEnvironment;
String? customDns;

void main(List<String> args) async {
  // Zone-level catch-all for anything that slips through both layers
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Cap the decoded image cache so a large library grid can't fill the
      // default 100 MB ceiling with full-resolution covers and OOM constrained
      // mobile heaps. Mobile gets a tight 64 MB.
      PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;

      // Widget-layer errors (build / layout / paint)
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details); // keep default red-screen in debug
        AppLogger.log(
          'FlutterError: ${details.exceptionAsString()}\n${details.stack}',
          logLevel: LogLevel.error,
        );
      };

      // Async errors that escape the Flutter framework (PlatformDispatcher)
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        AppLogger.log(
          'PlatformDispatcher error: $error\n$stack',
          logLevel: LogLevel.error,
        );
        return true; // handled — prevent app termination
      };

      await RustLib.init();
      await imgCropIsolate.start();
      await getIsolateService.start();

      final storage = StorageProvider();
      await storage.requestPermission();
      Object? startupError;
      try {
        isar = await storage.initDB(null, inspector: kDebugMode);
      } catch (e, st) {
        AppLogger.log('DB init failed: $e\n$st', logLevel: LogLevel.error);
        startupError = e;
      }
      runApp(
        startupError != null
            ? _StartupErrorApp(error: startupError.toString())
            : ProviderScope(child: MyApp(), retry: (retryCount, error) => null),
      );
      if (startupError == null) unawaited(_postLaunchInit(storage));
    },
    (Object error, StackTrace stack) {
      AppLogger.log(
        'runZonedGuarded error: $error\n$stack',
        logLevel: LogLevel.error,
      );
    },
  );
}

class _StartupErrorApp extends StatelessWidget {
  final String error;
  const _StartupErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to start Dokusho',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  error,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _postLaunchInit(StorageProvider storage) async {
  await AppLogger.init();
  unawaited(MDownloader.initializeIsolatePool(poolSize: 6));
  await storage.deleteBtDirectory();
  await webviewServer();
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  Uri? lastUri;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeDateFormatting();
    customDns = ref.read(customDnsStateProvider);
    _initDeepLinks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      MExtensionServerPlatform(ref).startServer();
      if (ref.read(clearChapterCacheOnAppLaunchStateProvider)) {
        // Watch before calling clearcache to keep it alive, so that _getTotalDiskSpace completes safely
        ref.watch(totalChapterCacheSizeStateProvider);
        ref
            .read(totalChapterCacheSizeStateProvider.notifier)
            .clearCache(showToast: false);
      }
    });
    unawaited(ref.read(scanLocalLibraryProvider.future));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Lock the app when going to background (if lock is enabled)
      final lockEnabled = isar.settings.getSync(227)!.appLockEnabled ?? false;
      if (lockEnabled) {
        ref.read(appUnlockedStateProvider.notifier).lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final followSystem = ref.watch(followSystemThemeStateProvider);
    final forcedDark = ref.watch(themeModeStateProvider);
    final themeMode = followSystem
        ? ThemeMode.system
        : (forcedDark ? ThemeMode.dark : ThemeMode.light);
    final locale = ref.watch(l10nLocaleStateProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final base = BotToastInit()(context, child);

        final isUnlocked = ref.watch(appUnlockedStateProvider);
        final lockEnabled = ref.watch(appLockEnabledStateProvider);
        if (lockEnabled && !isUnlocked) {
          return Stack(
            fit: StackFit.expand,
            children: [base, const AppLockScreen()],
          );
        }

        return base;
      },
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
      routeInformationProvider: router.routeInformationProvider,
      title: 'Dokusho',
      scrollBehavior: AllowScrollBehavior(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MExtensionServerPlatform(ref).stopServer();
    _linkSubscription?.cancel();
    stopwebviewServer();
    AppLogger.dispose();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      if (uri == lastUri) return; // Debouncing Deep Links
      lastUri = uri;
      switch (uri.host) {
        case "add-repo":
          final repoName = uri.queryParameters["repo_name"];
          final repoUrl = uri.queryParameters["repo_url"];
          final mangaRepoUrls = uri.queryParametersAll["manga_url"];
          final context = navigatorKey.currentContext;
          if (context == null || !context.mounted) return;
          final l10n = context.l10n;
          showDialog(
            context: navigatorKey.currentContext!,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text(l10n.add_repo),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${l10n.name}: ${repoName ?? 'Unknown'}"),
                    const SizedBox(height: 8),
                    Text("URL: ${repoUrl ?? 'Unknown'}"),
                  ],
                ),
                actions: [
                  TextButton(
                    child: Text(l10n.cancel),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  FilledButton(
                    child: Text(l10n.add),
                    onPressed: () async {
                      if (context.mounted) Navigator.of(context).pop();

                      final validUrls = await _checkValidUrls([
                        ...mangaRepoUrls ?? [],
                      ]);

                      if (!validUrls) {
                        botToast(l10n.unsupported_repo);
                        return;
                      }

                      void addRepos(ItemType type, List<String>? urls) {
                        if (urls == null) return;
                        final current = ref.read(
                          extensionsRepoStateProvider(type),
                        );
                        final updated = [
                          ...current,
                          ...urls.map(
                            (e) => Repo(
                              name: repoName,
                              jsonUrl: e,
                              website: repoUrl,
                            ),
                          ),
                        ];
                        ref
                            .read(extensionsRepoStateProvider(type).notifier)
                            .set(updated);
                      }

                      addRepos(ItemType.manga, mangaRepoUrls);
                      botToast(l10n.repo_added);
                    },
                  ),
                ],
              );
            },
          );
          break;
        case "add-button":
          final buttonDataRaw = uri.queryParametersAll["button"];
          final context = navigatorKey.currentContext;
          if (context == null || !context.mounted || buttonDataRaw == null) {
            return;
          }
          final l10n = context.l10n;
          for (final buttonRaw in buttonDataRaw) {
            final buttonData = jsonDecode(
              utf8.decode(base64.decode(buttonRaw)),
            );
            if (buttonData is Map<String, dynamic>) {
              final customButton = CustomButton.fromJson(buttonData);
              await showDialog(
                context: navigatorKey.currentContext!,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text(l10n.custom_buttons_add),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${l10n.name}: ${customButton.title ?? 'Unknown'}",
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        child: Text(l10n.cancel),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      FilledButton(
                        child: Text(l10n.add),
                        onPressed: () async {
                          if (context.mounted) Navigator.of(context).pop();
                          await isar.writeTxn(() async {
                            await isar.customButtons.put(
                              customButton
                                ..pos = await isar.customButtons.count()
                                ..isFavourite = false
                                ..id = null
                                ..updatedAt =
                                    DateTime.now().millisecondsSinceEpoch,
                            );
                          });
                          botToast(l10n.custom_buttons_added);
                        },
                      ),
                    ],
                  );
                },
              );
            }
          }
          break;
        default:
      }
    });
  }

  Future<bool> _checkValidUrls(List<String> urls) async {
    final http = MClient.init(reqcopyWith: {'useDartHttpClient': true});
    for (final url in urls) {
      final req = await http.get(Uri.parse(url));
      try {
        final sourceList = (jsonDecode(req.body) as List).map(
          (e) => Source.fromJson(e),
        );
        if (sourceList.firstOrNull?.name == null) {
          return false;
        }
      } catch (err) {
        return false;
      }
    }
    return true;
  }
}

class AllowScrollBehavior extends MaterialScrollBehavior {
  // This allows the scrollable widgets to be scrolled with touch, mouse, stylus,
  // inverted stylus, trackpad, and unknown pointer devices.
  // This is also useful for accessibility purposes, such as when using VoiceAccess,
  // which sends pointer events with unknown type when scrolling scrollables.
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}
