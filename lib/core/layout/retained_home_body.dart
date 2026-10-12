import 'package:flutter/material.dart';

/// Keep Home and Profile warm across tab switches. Map/camera/video-heavy tabs still
/// dispose normally; changing account/context disposes this entire subtree.
class RetainedHomeBody extends StatefulWidget {
  const RetainedHomeBody({
    super.key,
    required this.isHome,
    required this.home,
    required this.destination,
    this.isProfile = false,
    this.profile,
  }) : assert(!isProfile || profile != null),
       assert(!isHome || !isProfile);

  final bool isHome;
  final Widget home;
  final Widget destination;
  final bool isProfile;
  final Widget? profile;

  @override
  State<RetainedHomeBody> createState() => _RetainedHomeBodyState();
}

class _RetainedHomeBodyState extends State<RetainedHomeBody> {
  bool _visitedHome = false;
  bool _visitedProfile = false;

  @override
  Widget build(BuildContext context) {
    _visitedHome = _visitedHome || widget.isHome;
    _visitedProfile = _visitedProfile || widget.isProfile;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_visitedHome)
          Offstage(
            key: const ValueKey('retained-home'),
            offstage: !widget.isHome,
            child: TickerMode(enabled: widget.isHome, child: widget.home),
          ),
        if (_visitedProfile && widget.profile != null)
          Offstage(
            key: const ValueKey('retained-profile'),
            offstage: !widget.isProfile,
            child: TickerMode(
              enabled: widget.isProfile,
              child: widget.profile!,
            ),
          ),
        if (!widget.isHome && !widget.isProfile)
          KeyedSubtree(
            key: const ValueKey('active-destination'),
            child: widget.destination,
          ),
      ],
    );
  }
}
