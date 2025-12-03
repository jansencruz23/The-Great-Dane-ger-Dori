import 'package:flutter_gemini/flutter_gemini.dart';

void main() async {
  // Test your API key directly
  const apiKey = 'AIzaSyB1IxgOxPBPLFAgAZ80o95DtMIOn5doh70';
  
  print('Testing Gemini API with key: ${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}');
  
  Gemini.init(apiKey: apiKey);
  
  try {
    final response = await Gemini.instance.text('Say hello in one word');
    print('✅ SUCCESS! Response: ${response?.output}');
  } catch (e) {
    print('❌ FAILED! Error: $e');
  }
}
