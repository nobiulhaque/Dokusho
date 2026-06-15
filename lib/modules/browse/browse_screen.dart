import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar_community/isar.dart';
import 'package:dokusho/main.dart';
import 'package:dokusho/models/manga.dart';
import 'package:dokusho/models/source.dart';
import 'package:dokusho/providers/l10n_providers.dart';
import 'package:dokusho/providers/storage_provider.dart';
import 'package:dokusho/modules/browse/extension/extension_screen.dart';
import 'package:dokusho/modules/browse/explore_feed_screen.dart';
import 'package:dokusho/modules/library/widgets/search_text_form_field.dart';
import 'package:dokusho/services/fetch_sources_list.dart';
import 'package:dokusho/utils/item_type_localization.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with TickerProviderStateMixin {
  final _textEditingController = TextEditingController();
  late TabController _tabBarController;

  @override
  void initState() {
    super.initState();
    _tabBarController = TabController(length: 2, vsync: this);
    _tabBarController.addListener(() {
      _chekPermission();
      setState(() {
        _textEditingController.clear();
        _isSearch = false;
      });
    });
  }

  Future<void> _chekPermission() async {
    await StorageProvider().requestPermission();
  }

  @override
  void dispose() {
    _tabBarController.dispose();
    _textEditingController.dispose();
    super.dispose();
  }

  bool _isSearch = false;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nLocalizations(context)!;
    final isExtensionTab = _tabBarController.index == 1;

    return DefaultTabController(
      animationDuration: Duration.zero,
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          title: Text(
            l10n.browse,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          actions: [
            _isSearch
                ? SeachFormTextField(
                    onChanged: (value) {
                      setState(() {});
                    },
                    onSuffixPressed: () {
                      _textEditingController.clear();
                    },
                    onPressed: () {
                      setState(() {
                        _isSearch = false;
                      });
                      _textEditingController.clear();
                    },
                    controller: _textEditingController,
                  )
                : Row(
                    children: [
                      if (isExtensionTab)
                        IconButton(
                          onPressed: () {
                            context.push('/createExtension');
                          },
                          icon: Icon(
                            Icons.add_outlined,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      IconButton(
                        splashRadius: 20,
                        onPressed: () {
                          if (isExtensionTab) {
                            setState(() {
                              _isSearch = true;
                            });
                          } else {
                            context.push(
                              '/globalSearch',
                              extra: (null, ItemType.manga),
                            );
                          }
                        },
                        icon: Icon(
                          !isExtensionTab
                              ? Icons.travel_explore_rounded
                              : Icons.search_rounded,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
            IconButton(
              splashRadius: 20,
              onPressed: () {
                context.push(
                  isExtensionTab ? '/ExtensionLang' : '/sourceFilter',
                  extra: ItemType.manga,
                );
              },
              icon: Icon(
                !isExtensionTab
                    ? Icons.filter_list_sharp
                    : Icons.translate_rounded,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
          bottom: TabBar(
            indicatorSize: TabBarIndicatorSize.label,
            controller: _tabBarController,
            tabs: [
              const Tab(text: "Explore Feed"),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ItemType.manga.localizedExtensions(l10n)),
                    const SizedBox(width: 8),
                    _extensionUpdateNumbers(ref, ItemType.manga),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabBarController,
          children: [
            const ExploreFeedScreen(),
            ExtensionScreen(
              query: _textEditingController.text,
              itemType: ItemType.manga,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _extensionUpdateNumbers(WidgetRef ref, ItemType itemType) {
  return StreamBuilder(
    stream: isar.sources
        .filter()
        .idIsNotNull()
        .and()
        .isActiveEqualTo(true)
        .itemTypeEqualTo(itemType)
        .watch(fireImmediately: true),
    builder: (context, snapshot) {
      if (snapshot.hasData && snapshot.data!.isNotEmpty) {
        final entries = snapshot.data!
            .where(
              (element) =>
                  compareVersions(element.version!, element.versionLast!) < 0,
            )
            .toList();
        return entries.isEmpty
            ? const SizedBox.shrink()
            : Badge(
                backgroundColor: Theme.of(context).focusColor,
                label: Text(
                  entries.length.toString(),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall!.color,
                  ),
                ),
              );
      }
      return Container();
    },
  );
}
