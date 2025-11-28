import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_service.dart';

class ConsoleLogger {
  final AudioService audioService;
  StreamSubscription<AudioData>? _subscription;
  bool _isLogging = false;

  ConsoleLogger(this.audioService);

  void startLogging() {
    if (_isLogging) return;
    
    _isLogging = true;
    _subscription = audioService.audioDataStream.listen((audioData) {
      final prefix = audioData.type == 'system' ? '[SYSTEM]' : '[MIC]';
      debugPrint('$prefix ${audioData.data}');
    });
  }

  void stopLogging() {
    if (!_isLogging) return;
    
    _isLogging = false;
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopLogging();
  }
}

