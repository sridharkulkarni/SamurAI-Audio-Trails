import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';

// MTU size: 1KB max per chunk
const int maxChunkSize = 1024; // 1 KB

class WebSocketStreamService {
  IOWebSocketChannel? _channel;
  WebSocket? _socket;
  bool _isConnected = false;
  StreamSubscription? _subscription;
  Function(bool)? onConnectionStateChanged;
  
  bool get isConnected => _isConnected;
  
  Future<bool> connect(String url) async {
    try {
      print('Connecting to WebSocket: $url');
      
      // Disconnect existing connection if any
      if (_channel != null) {
        disconnect();
      }
      
      final uri = Uri.parse(url);
      
      // Use WebSocket.connect which actually waits for connection
      try {
        _socket = await WebSocket.connect(uri.toString()).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('WebSocket connection timeout');
          },
        );
        
        // Wrap the socket in an IOWebSocketChannel
        _channel = IOWebSocketChannel(_socket!);
        _isConnected = true;
        print('WebSocket connected successfully');
        onConnectionStateChanged?.call(true);
        
        // Listen for messages
        _subscription = _channel!.stream.listen(
          (message) {
            print('Received WebSocket message: $message');
          },
          onError: (error) {
            print('WebSocket error: $error');
            _isConnected = false;
            onConnectionStateChanged?.call(false);
          },
          onDone: () {
            print('WebSocket connection closed');
            _isConnected = false;
            onConnectionStateChanged?.call(false);
          },
          cancelOnError: true,
        );
        
        return true;
      } on TimeoutException catch (e) {
        print('WebSocket connection timeout: $e');
        _isConnected = false;
        return false;
      } on SocketException catch (e) {
        print('WebSocket connection error: $e');
        _isConnected = false;
        return false;
      } catch (e) {
        print('Error creating WebSocket connection: $e');
        _isConnected = false;
        return false;
      }
    } catch (e) {
      print('Error connecting to WebSocket: $e');
      _isConnected = false;
      return false;
    }
  }
  
  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    
    if (_channel != null) {
      try {
        _channel!.sink.close();
      } catch (e) {
        print('Error closing WebSocket channel: $e');
      }
      _channel = null;
    }
    
    if (_socket != null) {
      try {
        _socket!.close();
      } catch (e) {
        print('Error closing WebSocket: $e');
      }
      _socket = null;
    }
    
    _isConnected = false;
    onConnectionStateChanged?.call(false);
    print('WebSocket disconnected');
  }
  
  Future<bool> sendAudioChunk({
    required String source,
    required List<int> audioBytes,
    required String mimeType,
  }) async {
    if (!_isConnected || _channel == null) {
      // Silently fail if not connected (don't spam logs)
      return false;
    }
    
    try {
      // Handle empty chunks - send them anyway
      if (audioBytes.isEmpty) {
        final base64Audio = base64Encode(audioBytes);
        final payload = {
          'source': source,
          'audio': base64Audio,
          'mime': mimeType,
        };
        final jsonString = jsonEncode(payload);
        final jsonBytes = utf8.encode(jsonString);
        
        print('📤 WebSocket: Sending empty ${source} audio chunk (${jsonBytes.length} bytes JSON payload)');
        _channel!.sink.add(jsonString);
        return true;
      }
      
      // Split audio into 1KB chunks (MTU)
      int offset = 0;
      int chunkCount = 0;
      final totalBytes = audioBytes.length;
      
      while (offset < audioBytes.length) {
        final chunkSize = (offset + maxChunkSize < audioBytes.length) 
            ? maxChunkSize 
            : audioBytes.length - offset;
        
        final chunk = audioBytes.sublist(offset, offset + chunkSize);
        
        // Convert audio bytes to base64
        final base64Audio = base64Encode(chunk);
        
        // Create JSON payload
        final payload = {
          'source': source,
          'audio': base64Audio,
          'mime': mimeType,
        };
        
        final jsonString = jsonEncode(payload);
        final jsonBytes = utf8.encode(jsonString);
        
        // Log the message being sent
        chunkCount++;
        print('📤 WebSocket: Sending ${source} audio chunk #$chunkCount (${chunkSize} bytes audio, ${jsonBytes.length} bytes JSON payload)');
        
        _channel!.sink.add(jsonString);
        
        offset += chunkSize;
        
        // Small delay to avoid overwhelming the connection
        if (offset < audioBytes.length) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }
      
      if (chunkCount > 1) {
        print('📤 WebSocket: Sent $chunkCount chunks for ${source} audio (total: ${totalBytes} bytes)');
      }
      
      return true;
    } catch (e) {
      print('❌ Error sending audio chunk: $e');
      return false;
    }
  }
  
  void dispose() {
    disconnect();
  }
}

