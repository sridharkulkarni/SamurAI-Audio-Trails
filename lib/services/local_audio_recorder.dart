import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:desktop_audio_capture/audio_capture.dart';
import 'audio_service.dart';
import 'websocket_stream_service.dart';

class LocalAudioRecorder {
  final AudioService audioService;
  final WebSocketStreamService? webSocketService;
  
  StreamSubscription<AudioData>? _subscription;
  StreamSubscription<Uint8List>? _systemAudioSubscription;
  StreamSubscription<Uint8List>? _microphoneSubscription;
  bool _isStreaming = false;
  
  // Use desktop_audio_capture for system audio (macOS)
  SystemAudioCapture? _systemCapture;
  MicAudioCapture? _micCapture;
  
  // Audio format constants
  static const int sampleRate = 44100;
  static const int channels = 2;
  static const int sampleWidth = 2; // 16-bit = 2 bytes
  static const String mimeType = 'audio/pcm;rate=44100;channels=2;bitdepth=16';

  LocalAudioRecorder(this.audioService, {this.webSocketService});

  Future<bool> startStreaming(String type) async {
    if (webSocketService == null || !webSocketService!.isConnected) {
      print('WebSocket not connected, cannot start streaming');
      return false;
    }

    // Check if already streaming this type
    if ((type == 'system' && _systemAudioSubscription != null) ||
        (type == 'microphone' && _microphoneSubscription != null)) {
      print('Already streaming $type, skipping...');
      return true;
    }

    print('Starting audio streaming for $type...');
    _isStreaming = true;

    // Use desktop_audio_capture for macOS system audio
    if (type == 'system' && Platform.isMacOS) {
      print('Using desktop_audio_capture for system audio on macOS');
      return await _startSystemAudioCapture();
    } else if (type == 'microphone' && Platform.isMacOS) {
      print('Using desktop_audio_capture for microphone on macOS');
      return await _startMicrophoneCapture();
    }

    // Fallback to platform channel for other platforms or if desktop_audio_capture fails
    if (_subscription == null) {
      _subscription = audioService.audioDataStream.listen((audioData) {
        if (!_isStreaming) return;
        
        // Decode base64 and stream (including empty chunks)
        try {
          final audioBytes = base64Decode(audioData.data);
          
          // Debug: Log if empty but still send it
          if (audioBytes.isEmpty) {
            print('Info: Received empty audio data for ${audioData.type} - sending anyway');
          } else {
            // Check if all zeros
            final hasNonZero = audioBytes.any((byte) => byte != 0);
            if (!hasNonZero) {
              print('Info: Audio data is all zeros for ${audioData.type} - sending anyway');
            }
          }
          
          // Stream audio based on type (including empty chunks)
          if (audioData.type == 'system') {
            _streamAudioChunk('customer', audioBytes);
          } else if (audioData.type == 'microphone') {
            _streamAudioChunk('agent', audioBytes);
          }
        } catch (e) {
          print('Error decoding audio data: $e');
        }
      });
    }

    // Start platform channel capture
    if (type == 'system') {
      await audioService.startSystemAudioCapture();
    } else if (type == 'microphone') {
      await audioService.startMicrophoneCapture();
    }

    return true;
  }

  void _streamAudioChunk(String source, List<int> audioBytes) {
    // Double-check streaming flag before sending
    if (!_isStreaming) {
      return;
    }
    
    if (webSocketService == null || !webSocketService!.isConnected) {
      return;
    }
    
    // Stream audio chunk in background
    webSocketService!.sendAudioChunk(
      source: source,
      audioBytes: audioBytes,
      mimeType: mimeType,
    ).then((success) {
      if (!success) {
        print('Failed to stream audio chunk for $source');
      }
    }).catchError((error) {
      print('Error streaming audio chunk: $error');
    });
  }

  Future<bool> _startSystemAudioCapture() async {
    try {
      _systemCapture = SystemAudioCapture(
        config: SystemAudioConfig(
          sampleRate: 44100,
          channels: 2,
        ),
      );
      
      print('Starting system audio capture with desktop_audio_capture...');
      await _systemCapture!.startCapture();
      
      if (_systemCapture!.audioStream == null) {
        print('Warning: System audio stream is null');
        await _systemCapture!.stopCapture();
        return false;
      }
      
      _systemAudioSubscription = _systemCapture!.audioStream!.listen(
        (audioData) {
          if (!_isStreaming) return;
          
          // Stream audio as "customer" (speaker/system audio) - including empty chunks
          if (audioData.isEmpty) {
            print('Info: Received empty system audio data chunk - sending anyway');
          } else {
            // Check if all zeros
            final hasNonZero = audioData.any((byte) => byte != 0);
            if (!hasNonZero) {
              print('Info: System audio data is all zeros - sending anyway');
            }
          }
          
          _streamAudioChunk('customer', audioData);
        },
        onError: (error) {
          print('System audio stream error: $error');
        },
        onDone: () {
          print('System audio stream done');
        },
        cancelOnError: false,
      );
      
      print('System audio capture started successfully');
      return true;
    } catch (e, stackTrace) {
      print('Error starting system audio capture: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<bool> _startMicrophoneCapture() async {
    try {
      _micCapture = MicAudioCapture(
        config: MicAudioConfig(
          sampleRate: 44100,
          channels: 2,
        ),
      );
      
      print('Starting microphone capture with desktop_audio_capture...');
      await _micCapture!.startCapture();
      
      if (_micCapture!.audioStream == null) {
        print('Warning: Microphone audio stream is null');
        await _micCapture!.stopCapture();
        return false;
      }
      
      _microphoneSubscription = _micCapture!.audioStream!.listen(
        (audioData) {
          if (!_isStreaming) return;
          
          // Stream audio as "agent" (microphone audio) - including empty chunks
          if (audioData.isEmpty) {
            print('Info: Received empty microphone audio data chunk - sending anyway');
          } else {
            // Check if all zeros
            final hasNonZero = audioData.any((byte) => byte != 0);
            if (!hasNonZero) {
              print('Info: Microphone audio data is all zeros - sending anyway');
            }
          }
          
          _streamAudioChunk('agent', audioData);
        },
        onError: (error) {
          print('Microphone audio stream error: $error');
        },
        onDone: () {
          print('Microphone audio stream done');
        },
        cancelOnError: false,
      );
      
      print('Microphone capture started successfully');
      return true;
    } catch (e, stackTrace) {
      print('Error starting microphone capture: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<void> stopStreaming() async {
    print('Stopping audio streaming...');
    
    // Set streaming flag to false FIRST to prevent any new chunks from being sent
    _isStreaming = false;
    
    // Cancel all subscriptions immediately to stop receiving new data
    await _systemAudioSubscription?.cancel();
    _systemAudioSubscription = null;
    
    await _microphoneSubscription?.cancel();
    _microphoneSubscription = null;
    
    await _subscription?.cancel();
    _subscription = null;
    
    // Stop the desktop_audio_capture instances
    if (_systemCapture != null) {
      print('Stopping system audio capture...');
      try {
        await _systemCapture?.stopCapture();
      } catch (e) {
        print('Error stopping system capture: $e');
      }
      _systemCapture = null;
    }
    
    if (_micCapture != null) {
      print('Stopping microphone capture...');
      try {
        await _micCapture?.stopCapture();
      } catch (e) {
        print('Error stopping microphone capture: $e');
      }
      _micCapture = null;
    }
    
    // Stop platform channel capture
    try {
      await audioService.stopSystemAudioCapture();
      await audioService.stopMicrophoneCapture();
    } catch (e) {
      print('Error stopping platform channel capture: $e');
    }
    
    // Wait a bit to ensure all pending operations complete
    await Future.delayed(const Duration(milliseconds: 100));
    
    print('Audio streaming stopped');
  }

  void stopAll() {
    _isStreaming = false;
    
    _subscription?.cancel();
    _subscription = null;
    _systemAudioSubscription?.cancel();
    _systemAudioSubscription = null;
    _microphoneSubscription?.cancel();
    _microphoneSubscription = null;
    
    // Stop desktop_audio_capture
    _systemCapture?.stopCapture();
    _systemCapture = null;
    _micCapture?.stopCapture();
    _micCapture = null;
    
    // Stop platform channel capture
    audioService.stopSystemAudioCapture();
    audioService.stopMicrophoneCapture();
  }

  void dispose() {
    stopAll();
  }
}

