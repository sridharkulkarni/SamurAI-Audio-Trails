import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/local_audio_recorder.dart';
import '../services/websocket_stream_service.dart';
import '../widgets/audio_control_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AudioService _audioService;
  late final WebSocketStreamService _webSocketService;
  late final LocalAudioRecorder _audioRecorder;
  
  List<AudioDevice> _inputDevices = [];
  List<AudioDevice> _outputDevices = [];
  
  String? _selectedSystemAudioDeviceId;
  String? _selectedMicrophoneDeviceId;
  
  bool _isSystemAudioCapturing = false;
  bool _isMicrophoneCapturing = false;
  bool _isStreaming = false;
  
  static const String _webSocketUrl = 'ws://172.21.0.16:8000/audio';

  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
    _webSocketService = WebSocketStreamService();
    _webSocketService.onConnectionStateChanged = (connected) {
      if (mounted) {
        if (!connected && _isStreaming) {
          // Connection was lost, stop streaming
          _audioRecorder.stopStreaming();
        }
        setState(() {
          _isStreaming = connected;
        });
      }
    };
    _audioRecorder = LocalAudioRecorder(_audioService, webSocketService: _webSocketService);
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
        
        // Start streaming if streaming is active
        if (_isStreaming) {
          await _audioRecorder.startStreaming('system');
        }
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
        
        // Start streaming if streaming is active
        if (_isStreaming) {
          await _audioRecorder.startStreaming('microphone');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start microphone capture')),
        );
      }
    }
  }

  Future<void> _toggleStreaming() async {
    if (_isStreaming) {
      // Stop streaming
      await _audioRecorder.stopStreaming();
      _webSocketService.disconnect();
      
      setState(() {
        _isStreaming = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Streaming stopped')),
      );
    } else {
      // Connect to WebSocket and start streaming
      // Only set _isStreaming to true if connection actually succeeds
      final connected = await _webSocketService.connect(_webSocketUrl);
      
      if (connected && _webSocketService.isConnected) {
        setState(() {
          _isStreaming = true;
        });
        
        // Start streaming for active captures
        if (_isSystemAudioCapturing) {
          await _audioRecorder.startStreaming('system');
        }
        if (_isMicrophoneCapturing) {
          await _audioRecorder.startStreaming('microphone');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Streaming started')),
        );
      } else {
        // Connection failed - ensure streaming state is false
        setState(() {
          _isStreaming = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to WebSocket server'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _audioRecorder.stopStreaming();
    _webSocketService.disconnect();
    _audioService.stopSystemAudioCapture();
    _audioService.stopMicrophoneCapture();
    _audioRecorder.dispose();
    _webSocketService.dispose();
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
              // Start Streaming Button
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'WebSocket Streaming',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _webSocketUrl,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isStreaming ? Colors.green : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isStreaming ? 'Streaming' : 'Not Streaming',
                                    style: TextStyle(
                                      color: _isStreaming ? Colors.green : Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: _toggleStreaming,
                            icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
                            label: Text(_isStreaming ? 'Stop Streaming' : 'Start Streaming'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isStreaming ? Colors.red : Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // System Audio Card
              AudioControlCard(
                title: 'System Audio (Customer)',
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
                consoleOutputEnabled: false,
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
                onToggleConsoleOutput: null,
              ),
              const SizedBox(height: 24),
              // Microphone Card
              AudioControlCard(
                title: 'Microphone (Agent)',
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
                consoleOutputEnabled: false,
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
                onToggleConsoleOutput: null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

