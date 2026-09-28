import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/gif.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';

/// WhatsApp-style picker panel shown above the chat composer: three tabs —
/// Emoji | Stickers | GIF. The GIF tab only appears when the backend reports
/// the Tenor proxy as configured (GET /chat/gifs -> configured == true).
class EmojiStickerGifPanel extends StatefulWidget {
  final ThemeColors colors;

  /// Plain emoji tapped in the Emoji tab -> sent instantly as a text message.
  final void Function(String emoji) onEmojiSelected;

  /// Sticker tab -> sent as `{ content: emoji, messageType: 'sticker' }`.
  final void Function(String emoji) onStickerSelected;

  /// GIF tab -> sent as an `attachmentType: 'gif'` message.
  final void Function(GifObject gif) onGifSelected;

  /// Whether the backend GIF proxy is configured (GIF tab hidden otherwise).
  final bool gifsConfigured;

  const EmojiStickerGifPanel({
    super.key,
    required this.colors,
    required this.onEmojiSelected,
    required this.onStickerSelected,
    required this.onGifSelected,
    this.gifsConfigured = false,
  });

  /// Convenience wrapper: opens the panel in a rounded bottom sheet.
  static void show(
    BuildContext context, {
    required ThemeColors colors,
    required void Function(String emoji) onEmojiSelected,
    required void Function(String emoji) onStickerSelected,
    required void Function(GifObject gif) onGifSelected,
    bool gifsConfigured = false,
  }) {
    final hasGifs = gifsConfigured;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: EmojiStickerGifPanel(
          colors: colors,
          onEmojiSelected: onEmojiSelected,
          onStickerSelected: onStickerSelected,
          onGifSelected: onGifSelected,
          gifsConfigured: hasGifs,
        ),
      ),
    );
  }

  @override
  State<EmojiStickerGifPanel> createState() => _EmojiStickerGifPanelState();
}

class _EmojiStickerGifPanelState extends State<EmojiStickerGifPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _gifSearchController = TextEditingController();
  Timer? _gifDebounce;
  List<GifObject> _gifs = [];
  bool _gifsLoading = false;
  bool _gifsFailed = false;

  @override
  void initState() {
    super.initState();
    final tabs = widget.gifsConfigured ? 3 : 2;
    _tabController = TabController(length: tabs, vsync: this);
    if (widget.gifsConfigured) {
      _loadGifs('trending');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _gifDebounce?.cancel();
    _gifSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadGifs(String search) async {
    setState(() {
      _gifsLoading = true;
      _gifsFailed = false;
    });
    try {
      final result = await ApiService().getChatGifs(search: search, limit: 24);
      if (!mounted) return;
      setState(() {
        _gifs = result.gifs;
        _gifsLoading = false;
      });
    } catch (e) {
      Logger.error('GIF search failed: $e');
      if (!mounted) return;
      setState(() {
        _gifs = [];
        _gifsLoading = false;
        _gifsFailed = true;
      });
    }
  }

  void _onGifSearchChanged(String value) {
    _gifDebounce?.cancel();
    _gifDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadGifs(value.trim().isEmpty ? 'trending' : value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return SizedBox(
      height: 380,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: colors.primary,
            unselectedLabelColor: colors.textSecondary,
            indicatorColor: colors.primary,
            dividerColor: colors.border,
            tabs: [
              const Tab(text: 'Emoji'),
              const Tab(text: 'Stickers'),
              if (widget.gifsConfigured) const Tab(text: 'GIF'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEmojiGrid(colors),
                _buildStickerGrid(colors),
                if (widget.gifsConfigured) _buildGifTab(colors),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -- Emoji tab ---------------------------------------------------------------

  static const List<(String, List<String>)> _emojiCategories = [
    ('Smileys', [
      '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩',
      '😘','😗','😚','🥲','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨',
      '😐','😑','😶','😏','😒','🙄','😬','😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢',
      '🥵','🥶','🥴','😵','🤯','🤠','🥳','😎','🤓','🧐','😕','😟','🙁','😮','😲','😳',
      '🥺','😦','😨','😰','😥','😢','😭','😱','😖','😣','😞','😩','🥱','😤','😡','🤬',
    ]),
    ('Gestures', [
      '👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆',
      '👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','✍️','💪',
      '🦾','👀','👁️','👅','👄','🧠','🫶','💅','🤳',
    ]),
    ('Hearts', [
      '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖',
      '💘','💝','💟','♥️','💯','🔥','✨','⭐','🌟','💫','⚡','🎉','🎊','🎈','🎁','🏆',
    ]),
    ('Animals', [
      '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🐔',
      '🐧','🐦','🐤','🦆','🦅','🦉','🐺','🐴','🦄','🐝','🦋','🐌','🐞','🐢','🐍','🐙',
      '🦀','🐬','🐳','🦈','🐊','🐘','🦒','🦓','🦔','🐾','🌵','🌴','🌻','🌹','🌈','🍀',
    ]),
    ('Food', [
      '🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍒','🍑','🥭','🍍','🥥','🥝',
      '🍅','🥑','🥦','🌽','🥕','🍞','🥐','🧀','🍳','🥓','🍔','🍟','🍕','🌮','🌯','🍜',
      '🍣','🍩','🍪','🎂','🍰','🍭','🍫','🍿','☕','🍵','🥤','🍺','🍷','🥂','🧁','🥗',
    ]),
    ('Activities', [
      '⚽','🏀','🏈','⚾','🎾','🏐','🏓','🏸','🥊','🎯','🎮','🎲','🎳','🎼','🎤','🎧',
      '🎸','🎺','🎻','🥁','🎬','🎨','🏆','🥇','🎉','🚗','✈️','🚀','⛵','🏝️','🏔️','🎪',
    ]),
    ('Objects', [
      '⌚','📱','💻','⌨️','🖥️','💡','📚','📖','✏️','📝','📁','📅','📌','📎','🔒','🔑',
      '🔨','🔧','💰','💳','💎','🧲','🔬','🔭','📡','💊','🩹','🎁','🧸','🔔','🗝️','🕯️',
    ]),
  ];

  Widget _buildEmojiGrid(ThemeColors colors) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _emojiCategories.length,
      itemBuilder: (context, index) {
        final (label, emojis) = _emojiCategories[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                childAspectRatio: 1,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, i) {
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.onEmojiSelected(emojis[i]),
                  child: Center(
                    child: Text(emojis[i], style: const TextStyle(fontSize: 24)),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // -- Stickers tab --------------------------------------------------------------

  static const List<String> _stickers = [
    '😀','😂','🥰','😍','🤩','😜','🤪','🤗','🤔','😎','🥳','😴','🤯','🥺','😭','😡',
    '🤖','👻','🎃','🦄','🐸','🐼','🐨','🦁','🐧','🐢','🦋','🐝','🌸','🌻','🌹','🍀',
    '❤️','💔','💖','💯','🔥','✨','🎉','🎊','🎁','🏆','⚡','🌈','☀️','🌙','⭐','🍕',
    '🍔','🍟','🍩','🍰','☕','🎸','🎮','⚽','🏀','🚀','✈️','🏝️','💎','👑','🤝','👍',
  ];

  Widget _buildStickerGrid(ThemeColors colors) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 1,
      ),
      itemCount: _stickers.length,
      itemBuilder: (context, i) {
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onStickerSelected(_stickers[i]),
          child: Center(
            child: Text(_stickers[i], style: const TextStyle(fontSize: 48)),
          ),
        );
      },
    );
  }

  // -- GIF tab ---------------------------------------------------------------------

  Widget _buildGifTab(ThemeColors colors) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: TextField(
            controller: _gifSearchController,
            onChanged: _onGifSearchChanged,
            style: TextStyle(color: colors.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search GIFs…',
              hintStyle: TextStyle(color: colors.textSecondary),
              prefixIcon: Icon(Icons.search_rounded, color: colors.textSecondary, size: 20),
              isDense: true,
              filled: true,
              fillColor: colors.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: _gifsLoading
              ? Center(
                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
                )
              : _gifsFailed
                  ? Center(
                      child: Text(
                        'Could not load GIFs.\nPull to search again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                    )
                  : _gifs.isEmpty
                      ? Center(
                          child: Text(
                            'No GIFs found',
                            style: TextStyle(color: colors.textSecondary, fontSize: 13),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 1,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                          ),
                          itemCount: _gifs.length,
                          itemBuilder: (context, i) {
                            final gif = _gifs[i];
                            final preview =
                                (gif.previewUrl?.isNotEmpty ?? false) ? gif.previewUrl! : gif.url;
                            return GestureDetector(
                              onTap: () => widget.onGifSelected(gif),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: preview,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: colors.surfaceVariant,
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: colors.surfaceVariant,
                                        child: Icon(Icons.gif_rounded,
                                            color: colors.textSecondary),
                                      ),
                                    ),
                                    Positioned(
                                      left: 4,
                                      bottom: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'GIF',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
