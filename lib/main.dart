import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const AutoCropApp());
}

class AutoCropApp extends StatelessWidget {
  const AutoCropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Crop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
