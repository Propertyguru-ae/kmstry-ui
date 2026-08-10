import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_model.dart';

class UserCard extends StatelessWidget {
  final VenueCheckin user;
  final VoidCallback onTap;

  const UserCard({super.key, required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = user.displayPhoto;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          /// USER IMAGE
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }

              return Container(
                color: Colors.grey.shade200,
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black54,
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.shade300,
                child: const Icon(
                  Icons.person,
                  color: Colors.white70,
                  size: 32,
                ),
              );
            },
          ),

          if (user.isFeaturedVideo)
            const Positioned.fill(
              child: Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),

          /// GRADIENT OVERLAY
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withAlpha(180),
],
                ),
              ),
            ),
          ),

          /// USER NAME
          Positioned(
            bottom: 6,
            left: 6,
            right: 6,
            child: Text(
              user.fullName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
