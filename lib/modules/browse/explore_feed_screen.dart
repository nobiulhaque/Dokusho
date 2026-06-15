import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar_community/isar.dart';
import 'package:dokusho/main.dart';
import 'package:dokusho/models/manga.dart';
import 'package:dokusho/models/source.dart';
import 'package:dokusho/modules/widgets/manga_image_card_widget.dart';
import 'package:dokusho/modules/widgets/progress_center.dart';
import 'package:dokusho/services/get_popular.dart';
import 'package:dokusho/utils/extensions/build_context_extensions.dart';

class ExploreFeedScreen extends ConsumerStatefulWidget {
  const ExploreFeedScreen({super.key});

  @override
  ConsumerState<ExploreFeedScreen> createState() => _ExploreFeedScreenState();
}

class _ExploreFeedScreenState extends ConsumerState<ExploreFeedScreen> {
  final ScrollController _scrollController = ScrollController();
  List<Manga> _libraryMangas = [];
  StreamSubscription? _librarySubscription;

  @override
  void initState() {
    super.initState();
    _librarySubscription = isar.mangas
        .filter()
        .favoriteEqualTo(true)
        .watch(fireImmediately: true)
        .listen((mangas) {
      if (mounted) {
        setState(() {
          _libraryMangas = mangas;
        });
      }
    });
  }

  @override
  void dispose() {
    _librarySubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Source>>(
      stream: isar.sources
          .filter()
          .idIsNotNull()
          .isAddedEqualTo(true)
          .and()
          .isActiveEqualTo(true)
          .and()
          .itemTypeEqualTo(ItemType.manga)
          .watch(fireImmediately: true),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ProgressCenter();
        }

        final activeSources = snapshot.data ?? [];
        if (activeSources.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.explore_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "No extensions installed",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Install extensions from the Extensions tab to see content here.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          itemCount: activeSources.length,
          itemBuilder: (context, index) {
            final source = activeSources[index];
            return ExploreFeedRow(
              source: source,
              libraryMangas: _libraryMangas,
            );
          },
        );
      },
    );
  }
}

class ExploreFeedRow extends ConsumerWidget {
  final Source source;
  final List<Manga> libraryMangas;

  const ExploreFeedRow({
    super.key,
    required this.source,
    required this.libraryMangas,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popularAsync = ref.watch(getPopularProvider(source: source, page: 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12.0, right: 12.0, top: 16.0, bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                source.name ?? "Unknown Source",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  context.push('/mangaHome', extra: (source, false));
                },
                child: Row(
                  children: [
                    Text(
                      "View All",
                      style: TextStyle(color: context.primaryColor),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: context.primaryColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: popularAsync.when(
            data: (data) {
              if (data == null || data.list.isEmpty) {
                return const Center(
                  child: Text("No items found", style: TextStyle(color: Colors.grey)),
                );
              }

              final list = data.list;
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                itemCount: list.length > 15 ? 15 : list.length,
                itemBuilder: (context, index) {
                  final mManga = list[index];
                  final libraryManga = libraryMangas.firstWhereOrNull(
                    (m) => m.name == mManga.name && m.source == source.name,
                  );

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: SizedBox(
                      width: 110,
                      child: MangaImageCardWidget(
                        source: source,
                        getMangaDetail: mManga,
                        isComfortableGrid: true,
                        itemType: ItemType.manga,
                        libraryManga: libraryManga,
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(
              child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (err, stack) => Center(
              child: Text(
                "Error loading feed",
                style: TextStyle(color: Colors.red.shade400, fontSize: 12),
              ),
            ),
          ),
        ),
        const Divider(height: 24, thickness: 0.5),
      ],
    );
  }
}
