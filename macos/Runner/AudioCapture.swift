import Foundation
import AVFoundation
import CoreAudio

struct AudioDevice {
    let id: String
    let name: String
    let isInput: Bool
}

class AudioCapture: NSObject {
    private var systemAudioEngine: AVAudioEngine?
    private var microphoneEngine: AVAudioEngine?
    private var systemAudioNode: AVAudioInputNode?
    private var microphoneNode: AVAudioInputNode?
    private var systemAudioFormat: AVAudioFormat?
    private var microphoneFormat: AVAudioFormat?
    
    private var systemAudioCallback: ((Data) -> Void)?
    private var microphoneCallback: ((Data) -> Void)?
    
    private let sampleRate: Double = 44100.0
    private let channels: UInt32 = 2
    private let bitDepth: UInt32 = 16
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        // On macOS, we don't need AVAudioSession setup
        // Audio device access is handled through Core Audio
    }
    
    func getInputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        
        // Also get Core Audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        if status == noErr {
            let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
            var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
            
            status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &dataSize,
                &deviceIDs
            )
            
            if status == noErr {
                for deviceID in deviceIDs {
                    if let deviceName = getDeviceName(deviceID: deviceID) {
                        var isInput = false
                        var propertyAddress2 = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyStreams,
                            mScope: kAudioDevicePropertyScopeInput,
                            mElement: kAudioObjectPropertyElementMain
                        )
                        
                        var streamCount: UInt32 = 0
                        var dataSize2: UInt32 = 0
                        let status2 = AudioObjectGetPropertyDataSize(
                            deviceID,
                            &propertyAddress2,
                            0,
                            nil,
                            &dataSize2
                        )
                        
                        if status2 == noErr {
                            streamCount = dataSize2 / UInt32(MemoryLayout<AudioStreamID>.size)
                            isInput = streamCount > 0
                        }
                        
                        if isInput {
                            let deviceUID = getDeviceUID(deviceID: deviceID) ?? "\(deviceID)"
                            if !devices.contains(where: { $0.id == deviceUID }) {
                                devices.append(AudioDevice(
                                    id: deviceUID,
                                    name: deviceName,
                                    isInput: true
                                ))
                            }
                        }
                    }
                }
            }
        }
        
        return devices
    }
    
    func getOutputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        if status == noErr {
            let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
            var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
            
            status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &dataSize,
                &deviceIDs
            )
            
            if status == noErr {
                for deviceID in deviceIDs {
                    if let deviceName = getDeviceName(deviceID: deviceID) {
                        var isOutput = false
                        var propertyAddress2 = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyStreams,
                            mScope: kAudioDevicePropertyScopeOutput,
                            mElement: kAudioObjectPropertyElementMain
                        )
                        
                        var streamCount: UInt32 = 0
                        var dataSize2: UInt32 = 0
                        let status2 = AudioObjectGetPropertyDataSize(
                            deviceID,
                            &propertyAddress2,
                            0,
                            nil,
                            &dataSize2
                        )
                        
                        if status2 == noErr {
                            streamCount = dataSize2 / UInt32(MemoryLayout<AudioStreamID>.size)
                            isOutput = streamCount > 0
                        }
                        
                        if isOutput {
                            let deviceUID = getDeviceUID(deviceID: deviceID) ?? "\(deviceID)"
                            devices.append(AudioDevice(
                                id: deviceUID,
                                name: deviceName,
                                isInput: false
                            ))
                        }
                    }
                }
            }
        }
        
        return devices
    }
    
    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: Unmanaged<CFString>?
        var dataSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )
        
        if status == noErr, let nameUnmanaged = name {
            return nameUnmanaged.takeRetainedValue() as String
        }
        return nil
    }
    
    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: Unmanaged<CFString>?
        var dataSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )
        
        if status == noErr, let uidUnmanaged = uid {
            return uidUnmanaged.takeRetainedValue() as String
        }
        return nil
    }
    
    func startSystemAudioCapture(deviceId: String?, callback: @escaping (Data) -> Void) -> Bool {
        stopSystemAudioCapture()
        
        systemAudioEngine = AVAudioEngine()
        guard systemAudioEngine != nil else { return false }
        
        // For system audio, we'll use ScreenCaptureKit on macOS 13+
        // For older versions, we'll need to use a workaround
        if #available(macOS 13.0, *) {
            // Use ScreenCaptureKit for system audio
            return startSystemAudioCaptureWithScreenCaptureKit(callback: callback)
        } else {
            // Fallback: try to capture from default output device
            // Note: This won't work for true system audio loopback on older macOS
            return startSystemAudioCaptureLegacy(callback: callback)
        }
    }
    
    @available(macOS 13.0, *)
    private func startSystemAudioCaptureWithScreenCaptureKit(callback: @escaping (Data) -> Void) -> Bool {
        // ScreenCaptureKit requires screen recording permission
        // For now, we'll use a simpler approach with AVAudioEngine
        // capturing from the default output device
        return startSystemAudioCaptureLegacy(callback: callback)
    }
    
    private func startSystemAudioCaptureLegacy(callback: @escaping (Data) -> Void) -> Bool {
        // Note: True system audio loopback on macOS requires ScreenCaptureKit (macOS 13+)
        // or a virtual audio driver like BlackHole
        // This implementation captures from available audio sources
        
        systemAudioEngine = AVAudioEngine()
        guard let engine = systemAudioEngine else { return false }
        
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        
        // Convert to desired format if needed
        let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )
        
        let converter = AVAudioConverter(from: format, to: desiredFormat!)
        
        systemAudioCallback = { data in
            callback(data)
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self = self, let converter = converter, let desiredFormat = desiredFormat else { return }
            
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat, frameCapacity: buffer.frameLength)!
            
            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers.mData {
                let data = Data(bytes: audioBuffer, count: Int(outputBuffer.frameLength) * Int(desiredFormat.channelCount) * 2)
                self.systemAudioCallback?(data)
            }
        }
        
        do {
            try engine.start()
            return true
        } catch {
            print("Failed to start system audio capture: \(error)")
            return false
        }
    }
    
    func stopSystemAudioCapture() {
        systemAudioEngine?.stop()
        systemAudioEngine?.inputNode.removeTap(onBus: 0)
        systemAudioEngine = nil
        systemAudioCallback = nil
    }
    
    func startMicrophoneCapture(deviceId: String?, callback: @escaping (Data) -> Void) -> Bool {
        stopMicrophoneCapture()
        
        microphoneEngine = AVAudioEngine()
        guard let engine = microphoneEngine else { return false }
        
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        
        // Convert to desired format
        let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )
        
        let converter = AVAudioConverter(from: format, to: desiredFormat!)
        
        microphoneCallback = { data in
            callback(data)
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self = self, let converter = converter, let desiredFormat = desiredFormat else { return }
            
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat, frameCapacity: buffer.frameLength)!
            
            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers.mData {
                let data = Data(bytes: audioBuffer, count: Int(outputBuffer.frameLength) * Int(desiredFormat.channelCount) * 2)
                self.microphoneCallback?(data)
            }
        }
        
        do {
            try engine.start()
            return true
        } catch {
            print("Failed to start microphone capture: \(error)")
            return false
        }
    }
    
    func stopMicrophoneCapture() {
        microphoneEngine?.stop()
        microphoneEngine?.inputNode.removeTap(onBus: 0)
        microphoneEngine = nil
        microphoneCallback = nil
    }
}

