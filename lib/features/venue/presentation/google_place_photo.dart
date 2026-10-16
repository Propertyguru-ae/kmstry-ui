import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/media/media_network_url.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/venue/data/google_photo_source.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_report_options_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

typedef GooglePhotoSourceLoader = Future<GooglePhotoSource> Function(String);
typedef GooglePhotoLinkLauncher = Future<bool> Function(Uri);

/// Thumbnail provider details are loaded only when requested. The source badge opens a
/// sheet with the larger source photo and its full author attribution; the
/// thumbnail keeps its parent card's normal navigation.
class GooglePlacePhoto extends StatelessWidget {
  const GooglePlacePhoto(
    this.url, {
    super.key,
    this.mediaReference,
    this.fit = BoxFit.cover,
    this.errorWidget,
    this.sourceLoader,
    this.overlay,
    this.badgeBottom = 6,
    this.showSourceBadge = true,
    this.showAuthorAttribution = false,
  });
  final String url;
  final MediaReference? mediaReference;
  final BoxFit fit;
  final WidgetBuilder? errorWidget;
  final GooglePhotoSourceLoader? sourceLoader;
  final Widget? overlay;
  final double badgeBottom;
  // Compact photo strips supply the Google Maps credit beside the strip,
  // where the full provider name remains readable without covering a photo.
  final bool showSourceBadge;

  /// Large covers credit contributors on the photo itself. Compact thumbnails
  /// expose full attribution through the larger photo in the credits sheet.
  final bool showAuthorAttribution;

  @override
  Widget build(BuildContext context) {
    final isGooglePhoto = isGooglePlacePhotoProxyUrl(url);
    if (isGooglePhoto && showAuthorAttribution) {
      return _AttributedGooglePlacePhoto(photo: this);
    }
    return _buildPhoto(context);
  }

  Widget _buildPhoto(BuildContext context, {GooglePhotoSource? attribution}) {
    final photoUrl = attribution?.photoUrl ?? url;
    return CachedImage(
      photoUrl,
      // A refreshed source supplies an exact photo/author pair. An older
      // venue MediaReference must not substitute a different image here.
      mediaReference: attribution == null ? mediaReference : null,
      fit: fit,
      errorWidget: errorWidget,
      contentBuilder: (context, image, imageLoaded) => _buildContent(
        context,
        image,
        showCredits:
            isGooglePlacePhotoProxyUrl(photoUrl) &&
            imageLoaded &&
            (showSourceBadge || showAuthorAttribution),
        attribution: attribution,
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Widget image, {
    required bool showCredits,
    GooglePhotoSource? attribution,
  }) {
    if (!showCredits && overlay == null) return image;
    void open() => showGooglePhotoSourceSheet(
      context,
      photoUrl: attribution?.photoUrl ?? url,
      sourceLoader: attribution == null
          ? sourceLoader
          : (_) async => attribution,
    );
    final content = Stack(
      fit: StackFit.expand,
      children: [
        image,
        if (overlay != null) IgnorePointer(child: overlay!),
        if (showCredits)
          Positioned(
            left: attribution == null ? null : 6,
            right: 6,
            bottom: badgeBottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (attribution != null && attribution.authors.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(6),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final author in attribution.authors)
                          _InlineAuthor(author: author),
                      ],
                    ),
                  ),
                Semantics(
                  button: true,
                  label: 'Google Maps photo credits and source',
                  child: GestureDetector(
                    onTap: open,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'Google Maps · Credits',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return content;
  }
}

class _AttributedGooglePlacePhoto extends StatefulWidget {
  const _AttributedGooglePlacePhoto({required this.photo});
  final GooglePlacePhoto photo;

  @override
  State<_AttributedGooglePlacePhoto> createState() =>
      _AttributedGooglePlacePhotoState();
}

class _AttributedGooglePlacePhotoState
    extends State<_AttributedGooglePlacePhoto> {
  late Future<GooglePhotoSource> _source;

  Future<GooglePhotoSource> _load() => Future.sync(
    () =>
        (widget.photo.sourceLoader ??
        VenueContextRepository().getGooglePhotoSource)(widget.photo.url),
  );

  @override
  void initState() {
    super.initState();
    _source = _load();
  }

  @override
  void didUpdateWidget(covariant _AttributedGooglePlacePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.url != widget.photo.url ||
        oldWidget.photo.sourceLoader != widget.photo.sourceLoader) {
      _source = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GooglePhotoSource>(
    key: ValueKey(_source),
    future: _source,
    builder: (context, snapshot) {
      final source = snapshot.data;
      if (source != null) {
        return widget.photo._buildPhoto(context, attribution: source);
      }
      // Do not show a large photo with another photo's author or without its
      // required credits when the source endpoint is unavailable.
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: snapshot.hasError
              ? TextButton.icon(
                  onPressed: () {
                    final next = _load();
                    setState(() {
                      _source = next;
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry photo'),
                )
              : const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        ),
      );
    },
  );
}

class _InlineAuthor extends StatelessWidget {
  const _InlineAuthor({required this.author});
  final GooglePhotoAuthor author;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Photo by ${author.name}',
    link: author.profileUrl != null,
    child: GestureDetector(
      onTap: author.profileUrl == null
          ? null
          : () async {
              var opened = false;
              try {
                opened = await launchUrl(
                  author.profileUrl!,
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {
                /* Surface a retryable error without leaving the page. */
              }
              if (!opened && context.mounted) {
                showErrorToast(
                  context,
                  message: "Couldn't open Google Maps. Please try again.",
                );
              }
            },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 24, height: 24, child: _AuthorAvatar(author: author)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              author.name,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          if (author.profileUrl != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, color: Colors.white, size: 12),
          ],
        ],
      ),
    ),
  );
}

Future<void> showGooglePhotoSourceSheet(
  BuildContext context, {
  required String photoUrl,
  GooglePhotoSourceLoader? sourceLoader,
  GooglePhotoLinkLauncher? linkLauncher,
}) async {
  await showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheetContext) => GooglePhotoSourceSheet(
      photoUrl: photoUrl,
      sourceLoader: sourceLoader,
      linkLauncher: linkLauncher,
    ),
  );
}

class GooglePhotoSourceSheet extends StatefulWidget {
  const GooglePhotoSourceSheet({
    super.key,
    required this.photoUrl,
    this.sourceLoader,
    this.linkLauncher,
  });
  final String photoUrl;
  final GooglePhotoSourceLoader? sourceLoader;
  final GooglePhotoLinkLauncher? linkLauncher;

  @override
  State<GooglePhotoSourceSheet> createState() => _GooglePhotoSourceSheetState();
}

class _GooglePhotoSourceSheetState extends State<GooglePhotoSourceSheet> {
  late Future<GooglePhotoSource> _source;
  bool _openingLink = false;

  @override
  void initState() {
    super.initState();
    _source = _load();
  }

  @override
  void didUpdateWidget(covariant GooglePhotoSourceSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl ||
        oldWidget.sourceLoader != widget.sourceLoader) {
      _source = _load();
    }
  }

  Future<GooglePhotoSource> _load() => Future.sync(
    () =>
        (widget.sourceLoader ?? VenueContextRepository().getGooglePhotoSource)(
          widget.photoUrl,
        ),
  );

  Future<void> _open(Uri uri) async {
    if (_openingLink) return;
    setState(() => _openingLink = true);
    var opened = false;
    try {
      opened =
          await (widget.linkLauncher?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      /* Keep the sheet available so the user can retry. */
    }
    if (!mounted) return;
    setState(() => _openingLink = false);
    if (!opened) {
      showErrorToast(
        context,
        message: "Couldn't open Google Maps. Please try again.",
      );
    }
  }

  Future<void> _reportToGoogle(GooglePhotoSource source) async {
    if (_openingLink) return;
    if (!source.reportIsDirect) {
      final confirmed = await confirmGoogleReportNavigation(
        context,
        instructions:
            'Open the photo on Google Maps and choose Report a problem.',
      );
      if (!mounted || !confirmed) return;
    }
    await _open(source.reportUrl);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppSheetPalette.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSheetHeader(
                title: 'Photo credits',
                subtitle: 'This photo comes from Google Maps.',
              ),
              FutureBuilder<GooglePhotoSource>(
                // FutureBuilder otherwise retains the previous photo/author
                // while a replacement source is loading.
                key: ValueKey(_source),
                future: _source,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return _buildError(palette);
                  final source = snapshot.data;
                  if (source == null) {
                    return const SizedBox(
                      height: 96,
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.blue,
                          ),
                        ),
                      ),
                    );
                  }
                  return _buildSource(source);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(AppSheetPalette palette) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(Icons.image_not_supported_outlined, size: 40, color: palette.muted),
      const SizedBox(height: 10),
      Text(
        'Photo details are unavailable. Try again, or refresh the venue to load the latest photo.',
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.muted, fontSize: 13.5, height: 1.35),
      ),
      const SizedBox(height: 16),
      PrimaryButton.secondary(
        label: 'Try again',
        onPressed: () {
          final next = _load();
          setState(() {
            _source = next;
          });
        },
      ),
    ],
  );

  Widget _buildSource(GooglePhotoSource source) {
    final enabled = !_openingLink;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Use the photo returned together with these credits. A place-based
        // proxy can resolve to a different photo later; never reuse its old
        // thumbnail with fresh attribution. Google images remain memory-only.
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            color: Colors.black,
            height: MediaQuery.sizeOf(context).height * 0.36,
            child: CachedImage(
              source.photoUrl,
              key: ValueKey('credited-photo:${source.photoUrl}'),
              fit: BoxFit.contain,
              errorWidget: (_) => const Center(
                child: Text(
                  'Photo unavailable. Refresh the venue to try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (source.authors.isNotEmpty) ...[
          const AppSheetSectionLabel('Photo by'),
          AppSheetCard(
            children: [
              for (final author in source.authors)
                AppSheetRow(
                  leading: _AuthorAvatar(author: author),
                  title: author.name,
                  subtitle: 'Photo contributor',
                  showLink: author.profileUrl != null,
                  onTap: author.profileUrl == null || !enabled
                      ? null
                      : () => _open(author.profileUrl!),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        const AppSheetSectionLabel('Google Maps'),
        AppSheetCard(
          children: [
            AppSheetRow(
              leading: const AppSheetIconTile(
                icon: Icons.map_outlined,
                color: AppColors.blue,
              ),
              title: 'View on Google Maps',
              showLink: true,
              onTap: enabled ? () => _open(source.sourceUrl) : null,
            ),
            AppSheetRow(
              leading: const AppSheetIconTile(
                icon: Icons.outlined_flag_rounded,
                color: AppColors.orange,
              ),
              title: 'Report to Google Maps',
              subtitle:
                  'Optional. This report is reviewed by Google, not KMSTRY.',
              showLink: true,
              onTap: enabled ? () => _reportToGoogle(source) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.author});
  final GooglePhotoAuthor author;

  @override
  Widget build(BuildContext context) {
    final initial = author.name.trim().isEmpty
        ? '?'
        : author.name.trim()[0].toUpperCase();
    final fallback = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.blue.withValues(alpha: 0.16),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.blue,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final photo = author.photoUrl;
    if (photo == null) return fallback;
    return ClipOval(
      child: Image.network(
        photo.toString(),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
