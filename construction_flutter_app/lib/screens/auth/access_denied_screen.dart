import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/design_tokens.dart';

class AccessDeniedScreen extends StatelessWidget {
  final String error;
  const AccessDeniedScreen({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DFColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.gpp_bad_rounded, color: DFColors.critical, size: 80),
              const SizedBox(height: 24),
              Text('DATABASE ACCESS DENIED', 
                style: DFTextStyles.screenTitle.copyWith(color: DFColors.critical, fontSize: 24)),
              const SizedBox(height: 16),
              const Text(
                'This error usually happens because the Firebase Security Rules are blocking access. '
                'To fix this for yourself and others (like your brother), you must update your Firestore Rules in the Firebase Console.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Copy these rules to Firebase Console:', 
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    const Text(
                      'rules_version = "2";\nservice cloud.firestore {\n  match /databases/{database}/documents {\n    match /{document=**} {\n      allow read, write: if request.auth != null;\n    }\n  }\n}',
                      style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: 'rules_version = "2";\nservice cloud.firestore {\n  match /databases/{database}/documents {\n    match /{document=**} {\n      allow read, write: if request.auth != null;\n    }\n  }\n}'));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rules copied to clipboard!')));
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy Rules'),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => SystemNavigator.pop(),
                style: ElevatedButton.styleFrom(backgroundColor: DFColors.primaryStitch),
                child: const Text('Exit App', style: TextStyle(color: Colors.white)),
              ),
              TextButton(
                onPressed: () {
                  // Try to go back to login
                  Navigator.of(context).pushReplacementNamed('/login');
                },
                child: const Text('Return to Login'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
