import 'dart:io';

void main() {
  final file = File(
    r'c:\code\gdg-hau\dory-5\The-Great-Dane-ger-Dori\lib\screens\auth\login_screen.dart',
  );
  var content = file.readAsStringSync();

  // Pattern to find Positioned widgets (shapes 2-10)
  final patterns = [
    // Shape 2
    RegExp(r'Positioned\(\s+bottom: 120,\s+right: 20,'),
    // Shape 3
    RegExp(r'Positioned\(\s+top: 280,\s+right: 60,'),
    // Add more as needed
  ];

  int shapeIndex = 1; // Start from 1 since shape 0 is done

  for (var pattern in patterns) {
    if (content.contains(pattern)) {
      print('Found shape $shapeIndex');
      shapeIndex++;
    }
  }
}
