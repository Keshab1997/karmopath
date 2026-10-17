import 'package:flutter/material.dart';

import '../design_system/karmopath_theme.dart';

class KarmopathApp extends StatelessWidget {
  const KarmopathApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Karmopath',
    theme: KarmopathTheme.light(),
    home: Scaffold(
      appBar: AppBar(title: const Text('Karmopath · কর্মপথ')),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'কোনো ডেডলাইন আর মিস নয়।',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 24),
              Text('Foundation preview — app features are under development.'),
              SizedBox(height: 16),
              Text(
                'Independent information platform. Not affiliated with any government entity.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
