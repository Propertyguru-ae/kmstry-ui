import 'dart:io';
import 'package:flutter/material.dart';

class PreviewScreen extends StatelessWidget {
  final File file;

  const PreviewScreen({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.file(
              file,
              fit: BoxFit.cover,
            ),
          ),

          Positioned(
            bottom: 40,
            left: 30,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // retake
              },
              child: const Text("Retake"),
            ),
          ),

          Positioned(
            bottom: 40,
            right: 30,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); 
                Navigator.pop(context, file);
              },
              child: const Text("Use Photo"),
            ),
          ),
        ],
      ),
    );
  }
}
