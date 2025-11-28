import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/console_logger.dart';
import '../widgets/audio_control_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AudioService _audioService;
  late final ConsoleLogger _consoleLogger;
  
  List<AudioDevice> _inputDevices = [];
  List<AudioDevice> _outputDevices = [];
  
  String? _selectedSystemAudioDeviceId;
  String? _selectedMicrophoneDeviceId;
  
  bool _isSystemAudioCapturing = false;
  bool _isMicrophoneCapturing = false;
  
  bool _systemConsoleOutputEnabled = false;
  bool _microphoneConsoleOutputEnabled = false;

  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
    _consoleLogger = ConsoleLogger(_audioService);
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final inputDevices = await _audioService.getInputDevices();
    final outputDevices = await _audioService.getOutputDevices();
    
    setState(() {
      _inputDevices = inputDevices;
      _outputDevices = outputDevices;
      
      // Set default devices
      if (_inputDevices.isNotEmpty && _selectedMicrophoneDeviceId == null) {
        _selectedMicrophoneDeviceId = _inputDevices.first.id;
      }
      if (_outputDevices.isNotEmpty && _selectedSystemAudioDeviceId == null) {
        _selectedSystemAudioDeviceId = _outputDevices.first.id;
      }
    });
  }

  Future<void> _toggleSystemAudioCapture() async {
    if (_isSystemAudioCapturing) {
      await _audioService.stopSystemAudioCapture();
      setState(() {
        _isSystemAudioCapturing = false;
      });
    } else {
      final success = await _audioService.startSystemAudioCapture(
        deviceId: _selectedSystemAudioDeviceId,
      );
      if (success) {
        setState(() {
          _isSystemAudioCapturing = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start system audio capture')),
        );
      }
    }
  }

  Future<void> _toggleMicrophoneCapture() async {
    if (_isMicrophoneCapturing) {
      await _audioService.stopMicrophoneCapture();
      setState(() {
        _isMicrophoneCapturing = false;
      });
    } else {
      final success = await _audioService.startMicrophoneCapture(
        deviceId: _selectedMicrophoneDeviceId,
      );
      if (success) {
        setState(() {
          _isMicrophoneCapturing = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start microphone capture')),
        );
      }
    }
  }

  void _toggleSystemConsoleOutput() {
    setState(() {
      _systemConsoleOutputEnabled = !_systemConsoleOutputEnabled;
      if (_systemConsoleOutputEnabled) {
        _consoleLogger.startLogging();
      } else {
        _consoleLogger.stopLogging();
      }
    });
  }

  void _toggleMicrophoneConsoleOutput() {
    setState(() {
      _microphoneConsoleOutputEnabled = !_microphoneConsoleOutputEnabled;
      if (_microphoneConsoleOutputEnabled) {
        _consoleLogger.startLogging();
      } else {
        _consoleLogger.stopLogging();
      }
    });
  }

  @override
  void dispose() {
    _audioService.stopSystemAudioCapture();
    _audioService.stopMicrophoneCapture();
    _consoleLogger.dispose();
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Capture'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
            tooltip: 'Refresh Devices',
          ),
        ],
      ),
      body: Container(
        color: Colors.grey[50],
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // System Audio Card
              AudioControlCard(
                title: 'System Audio',
                selectedDeviceName: _outputDevices
                    .firstWhere(
                      (d) => d.id == _selectedSystemAudioDeviceId,
                      orElse: () => _outputDevices.isNotEmpty
                          ? _outputDevices.first
                          : AudioDevice(id: '', name: 'No devices', isInput: false),
                    )
                    .name,
                devices: _outputDevices
                    .map((d) => {'id': d.id, 'name': d.name})
                    .toList(),
                isCapturing: _isSystemAudioCapturing,
                consoleOutputEnabled: _systemConsoleOutputEnabled,
                onDeviceChanged: (deviceName) {
                  final device = _outputDevices.firstWhere(
                    (d) => d.name == deviceName,
                    orElse: () => _outputDevices.first,
                  );
                  setState(() {
                    _selectedSystemAudioDeviceId = device.id;
                  });
                },
                onToggleCapture: _toggleSystemAudioCapture,
                onToggleConsoleOutput: _toggleSystemConsoleOutput,
              ),
              const SizedBox(height: 24),
              // Microphone Card
              AudioControlCard(
                title: 'Microphone',
                selectedDeviceName: _inputDevices
                    .firstWhere(
                      (d) => d.id == _selectedMicrophoneDeviceId,
                      orElse: () => _inputDevices.isNotEmpty
                          ? _inputDevices.first
                          : AudioDevice(id: '', name: 'No devices', isInput: true),
                    )
                    .name,
                devices: _inputDevices
                    .map((d) => {'id': d.id, 'name': d.name})
                    .toList(),
                isCapturing: _isMicrophoneCapturing,
                consoleOutputEnabled: _microphoneConsoleOutputEnabled,
                onDeviceChanged: (deviceName) {
                  final device = _inputDevices.firstWhere(
                    (d) => d.name == deviceName,
                    orElse: () => _inputDevices.first,
                  );
                  setState(() {
                    _selectedMicrophoneDeviceId = device.id;
                  });
                },
                onToggleCapture: _toggleMicrophoneCapture,
                onToggleConsoleOutput: _toggleMicrophoneConsoleOutput,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

