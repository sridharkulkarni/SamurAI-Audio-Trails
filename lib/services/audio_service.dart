import 'dart:async';
import 'package:flutter/services.dart';

class AudioDevice {
  final String id;
  final String name;
  final bool isInput;

  AudioDevice({
    required this.id,
    required this.name,
    required this.isInput,
  });

  factory AudioDevice.fromMap(Map<dynamic, dynamic> map) {
    return AudioDevice(
      id: map['id'] as String,
      name: map['name'] as String,
      isInput: map['isInput'] as bool,
    );
  }
}

class AudioService {
  static const MethodChannel _channel = MethodChannel('com.samurai.audio_capture');
  
  final StreamController<AudioData> _audioDataController = StreamController<AudioData>.broadcast();
  
  Stream<AudioData> get audioDataStream => _audioDataController.stream;

  AudioService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onAudioData') {
      final Map<dynamic, dynamic> data = call.arguments as Map<dynamic, dynamic>;
      final audioData = AudioData(
        type: data['type'] as String,
        data: data['data'] as String, // base64 string
        size: data['size'] as int,
      );
      _audioDataController.add(audioData);
    }
  }

  Future<List<AudioDevice>> getInputDevices() async {
    try {
      final List<dynamic> devices = await _channel.invokeMethod('getInputDevices');
      return devices.map((device) => AudioDevice.fromMap(device as Map<dynamic, dynamic>)).toList();
    } catch (e) {
      print('Error getting input devices: $e');
      return [];
    }
  }

  Future<List<AudioDevice>> getOutputDevices() async {
    try {
      final List<dynamic> devices = await _channel.invokeMethod('getOutputDevices');
      return devices.map((device) => AudioDevice.fromMap(device as Map<dynamic, dynamic>)).toList();
    } catch (e) {
      print('Error getting output devices: $e');
      return [];
    }
  }

  Future<bool> startSystemAudioCapture({String? deviceId}) async {
    try {
      final bool result = await _channel.invokeMethod('startSystemAudioCapture', {
        'deviceId': deviceId,
      });
      return result;
    } catch (e) {
      print('Error starting system audio capture: $e');
      return false;
    }
  }

  Future<bool> stopSystemAudioCapture() async {
    try {
      final bool result = await _channel.invokeMethod('stopSystemAudioCapture');
      return result;
    } catch (e) {
      print('Error stopping system audio capture: $e');
      return false;
    }
  }

  Future<bool> startMicrophoneCapture({String? deviceId}) async {
    try {
      final bool result = await _channel.invokeMethod('startMicrophoneCapture', {
        'deviceId': deviceId,
      });
      return result;
    } catch (e) {
      print('Error starting microphone capture: $e');
      return false;
    }
  }

  Future<bool> stopMicrophoneCapture() async {
    try {
      final bool result = await _channel.invokeMethod('stopMicrophoneCapture');
      return result;
    } catch (e) {
      print('Error stopping microphone capture: $e');
      return false;
    }
  }

  void dispose() {
    _audioDataController.close();
  }
}

class AudioData {
  final String type; // 'system' or 'microphone'
  final String data; // base64 encoded audio data
  final int size; // size in bytes

  AudioData({
    required this.type,
    required this.data,
    required this.size,
  });
}

