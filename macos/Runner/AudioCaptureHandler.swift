import FlutterMacOS
import Foundation

class AudioCaptureHandler: NSObject, FlutterPlugin {
    private var audioCapture: AudioCapture?
    private var methodChannel: FlutterMethodChannel?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.samurai.audio_capture",
                                          binaryMessenger: registrar.messenger)
        let instance = AudioCaptureHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.methodChannel = channel
    }
    
    override init() {
        super.init()
        audioCapture = AudioCapture()
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let audioCapture = audioCapture else {
            result(FlutterError(code: "INIT_ERROR", message: "Audio capture not initialized", details: nil))
            return
        }
        
        switch call.method {
        case "getInputDevices":
            let devices = audioCapture.getInputDevices()
            let deviceList = devices.map { device in
                [
                    "id": device.id,
                    "name": device.name,
                    "isInput": device.isInput
                ]
            }
            result(deviceList)
            
        case "getOutputDevices":
            let devices = audioCapture.getOutputDevices()
            let deviceList = devices.map { device in
                [
                    "id": device.id,
                    "name": device.name,
                    "isInput": device.isInput
                ]
            }
            result(deviceList)
            
        case "startSystemAudioCapture":
            let args = call.arguments as? [String: Any]
            let deviceId = args?["deviceId"] as? String
            
            let success = audioCapture.startSystemAudioCapture(deviceId: deviceId) { [weak self] data in
                self?.onAudioData(data: data, isSystemAudio: true)
            }
            
            if success {
                result(true)
            } else {
                result(FlutterError(code: "CAPTURE_ERROR", message: "Failed to start system audio capture", details: nil))
            }
            
        case "stopSystemAudioCapture":
            audioCapture.stopSystemAudioCapture()
            result(true)
            
        case "startMicrophoneCapture":
            let args = call.arguments as? [String: Any]
            let deviceId = args?["deviceId"] as? String
            
            let success = audioCapture.startMicrophoneCapture(deviceId: deviceId) { [weak self] data in
                self?.onAudioData(data: data, isSystemAudio: false)
            }
            
            if success {
                result(true)
            } else {
                result(FlutterError(code: "CAPTURE_ERROR", message: "Failed to start microphone capture", details: nil))
            }
            
        case "stopMicrophoneCapture":
            audioCapture.stopMicrophoneCapture()
            result(true)
            
        case "convertToMp3":
            let args = call.arguments as? [String: Any]
            let wavPath = args?["wavPath"] as? String
            let mp3Path = args?["mp3Path"] as? String
            
            guard let wavPath = wavPath, let mp3Path = mp3Path else {
                result(FlutterError(code: "INVALID_ARGS", message: "wavPath and mp3Path are required", details: nil))
                return
            }
            
            let success = convertWavToMp3(wavPath: wavPath, mp3Path: mp3Path)
            result(success)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func onAudioData(data: Data, isSystemAudio: Bool) {
        // Convert to base64
        let base64 = data.base64EncodedString()
        
        // Print to console
        print("\(isSystemAudio ? "[SYSTEM]" : "[MIC]") \(base64)")
        
        // Send to Flutter
        let eventData: [String: Any] = [
            "type": isSystemAudio ? "system" : "microphone",
            "data": base64,
            "size": data.count
        ]
        
        methodChannel?.invokeMethod("onAudioData", arguments: eventData)
    }
    
    private func convertWavToMp3(wavPath: String, mp3Path: String) -> Bool {
        // Check if WAV file exists
        guard FileManager.default.fileExists(atPath: wavPath) else {
            print("Error: WAV file does not exist at path: \(wavPath)")
            return false
        }
        
        let process = Process()
        var ffmpegPath: String?
        
        // Try common ffmpeg locations
        let possiblePaths = [
            "/opt/homebrew/bin/ffmpeg",  // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",      // Intel Homebrew
            "/usr/bin/ffmpeg"             // System installation
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                ffmpegPath = path
                break
            }
        }
        
        if let ffmpegPath = ffmpegPath {
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = ["-i", wavPath, "-codec:a", "libmp3lame", "-b:a", "192k", "-y", mp3Path]
        } else {
            // Try to find ffmpeg in PATH using /usr/bin/env
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["ffmpeg", "-i", wavPath, "-codec:a", "libmp3lame", "-b:a", "192k", "-y", mp3Path]
        }
        
        // Capture output for debugging
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            print("Converting WAV to MP3: \(wavPath) -> \(mp3Path)")
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                // Check if MP3 file was created
                if FileManager.default.fileExists(atPath: mp3Path) {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: mp3Path),
                       let fileSize = attributes[.size] as? Int64 {
                        print("MP3 conversion successful. File size: \(fileSize) bytes")
                    } else {
                        print("MP3 conversion successful. File created at \(mp3Path)")
                    }
                    return true
                } else {
                    print("Error: MP3 file was not created at \(mp3Path)")
                    return false
                }
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("ffmpeg conversion failed with exit code \(process.terminationStatus)")
                print("ffmpeg output: \(output)")
                return false
            }
        } catch {
            print("Error running ffmpeg: \(error)")
            print("Note: ffmpeg must be installed. Install with: brew install ffmpeg")
            return false
        }
    }
}

