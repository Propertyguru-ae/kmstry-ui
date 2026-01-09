import 'package:flutter/material.dart';

class MomentsViewerPage extends StatelessWidget {
  final List<String> images;
  final int initialIndex;

  const MomentsViewerPage({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: PageController(initialPage: initialIndex),
            itemCount: images.length,
            itemBuilder: (context, index) {
              return Center(
                child: InteractiveViewer(
                  child: Image.network(
                    images[index],
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),

          /// CLOSE BUTTON
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
