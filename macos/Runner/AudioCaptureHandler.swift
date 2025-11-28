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
}

