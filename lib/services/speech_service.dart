import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  String _currentTranscript = '';

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  String get currentTranscript => _currentTranscript;

  // Initialize speech recognition
  Future<bool> initialize() async {
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) => print('Speech recognition error: $error'),
        onStatus: (status) => print('Speech recognition status: $status'),
      );
      return _isInitialized;
    } catch (e) {
      print('Speech recognition initialization failed: $e');
      return false;
    }
  }

  // Start listening
  Future<void> startListening({
    required Function(String) onResult,
    Function? onDone,
  }) async {
    if (!_isInitialized) {
      throw 'Speech recognition not initialized';
    }

    _currentTranscript = '';

    await _speech.listen(
      onResult: (result) {
        _currentTranscript = result.recognizedWords;
        onResult(_currentTranscript);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      ),
    );

    _isListening = true;
  }

  // Stop listening
  Future<String> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }

    return _currentTranscript;
  }

  // Cancel listening
  Future<void> cancelListening() async {
    if (_isListening) {
      await _speech.cancel();
      _isListening = false;
      _currentTranscript = '';
    }
  }

  // Check if speech recognition is available
  Future<bool> hasPermission() async {
    return await _speech.initialize();
  }

  // Get available locales
  Future<List<stt.LocaleName>> getLocales() async {
    if (!_isInitialized) return [];
    return await _speech.locales();
  }

  // Dispose
  void dispose() {
    _speech.stop();
    _isInitialized = false;
    _isListening = false;
  }
}
