import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/user_card.dart';

class VenuePeoplePage extends StatefulWidget {
  final Venue venue;

  /// Backend check-in list uses the DB venue UUID. Google-sourced [venue] may
  /// use [placeId] as [Venue.id]; pass the resolved id from active check-in / resolve.
  final String? listVenueId;

  const VenuePeoplePage({
    super.key,
    required this.venue,
    this.listVenueId,
  });

  @override
  State<VenuePeoplePage> createState() => _VenuePeoplePageState();
}

class _VenuePeoplePageState extends State<VenuePeoplePage> {
  final _repo = VenueCheckinRepository();
  late Future<List<VenueCheckin>> _future;
  @override
  void initState() {
    super.initState();
    _loadCheckins();
  }

  String get _effectiveVenueIdForList =>
      (widget.listVenueId != null && widget.listVenueId!.isNotEmpty)
          ? widget.listVenueId!
          : widget.venue.id;

  void _loadCheckins() {
    setState(() {
      _future = _repo.getWhoIsHere(_effectiveVenueIdForList);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: colors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: colors.onSurface,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: false,
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
                ),

                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.venue.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FutureBuilder<List<VenueCheckin>>(
                            future: _future,
                            builder: (_, snapshot) {
                              if (!snapshot.hasData) return const SizedBox();

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  snapshot.data!.length.toString(),
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Live now",
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Divider(
            height: 1,
            thickness: 0.5,
            color: colors.onSurface.withValues(alpha: 0.2),
          ),
          Expanded(
            child: FutureBuilder<List<VenueCheckin>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  debugPrint('❌ VenuePeople error: ${snapshot.error}');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: colors.secondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load people',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getErrorMessage(snapshot.error),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadCheckins,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final people = snapshot.data!;

                if (people.isEmpty) {
                  return Center(
                    child: Text(
                      'No one is here yet',
                      style: TextStyle(color: colors.onSurface),
                    ),
                  );
                }

                return GridView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: people.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 1.5,
                    crossAxisSpacing: 1.5,
                    childAspectRatio: 0.7,
                  ),
                  itemBuilder: (context, index) {
                    final person = people[index];

                    return UserCard(
                      user: person,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfilePreviewPage(
                              checkinId: person.id,
                              venueId: _effectiveVenueIdForList,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getErrorMessage(Object? error) {
    final errorString = error.toString();
    if (errorString.contains('UnAuth')) {
      return 'Authentication required. Please log in again.';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out. Please check your connection.';
    } else if (errorString.contains('SocketException') || 
               errorString.contains('Failed host lookup')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorString.contains('statusCode')) {
      // Extract status code from error message
      final match = RegExp(r'\((\d+)\)').firstMatch(errorString);
      if (match != null) {
        final statusCode = match.group(1);
        if (statusCode == '401') {
          return 'Unauthorized. Please log in again.';
        } else if (statusCode == '403') {
          return 'Access denied.';
        } else if (statusCode == '404') {
          return 'Venue not found.';
        } else if (statusCode == '500') {
          return 'Server error. Please try again later.';
        }
        return 'Error $statusCode: ${errorString.split(':').last.trim()}';
      }
    }
    return errorString;
  }
}
