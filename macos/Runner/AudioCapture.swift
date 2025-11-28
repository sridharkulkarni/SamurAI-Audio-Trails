import Foundation
import AVFoundation
import CoreAudio
import CoreMedia
import ScreenCaptureKit

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
    
    // ScreenCaptureKit properties (macOS 13+)
    private var screenCaptureStream: Any? // SCStream on macOS 13+
    private var screenCaptureContentFilter: Any? // SCContentFilter on macOS 13+
    
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
        // Check permission first
        let legacyCallback = { [weak self] in
            guard let self = self else { return }
            _ = self.startSystemAudioCaptureLegacy(callback: callback)
        }
        
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    print("No display found for ScreenCaptureKit")
                    legacyCallback()
                    return
                }
                
                // Create content filter for system audio
                let filter = SCContentFilter(display: display, excludingWindows: [])
                self.screenCaptureContentFilter = filter as Any
                
                // Create stream configuration
                let streamConfig = SCStreamConfiguration()
                streamConfig.capturesAudio = true
                streamConfig.excludesCurrentProcessAudio = false
                streamConfig.sampleRate = 44100
                streamConfig.channelCount = 2
                
                // Create audio stream output handler
                let streamOutput = AudioStreamOutput(callback: callback)
                let streamDelegate = StreamDelegate()
                
                // Create and start stream
                let stream = SCStream(filter: filter, configuration: streamConfig, delegate: streamDelegate)
                
                // Add stream output for audio
                try stream.addStreamOutput(streamOutput, type: .audio, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
                
                // Use async version of startCapture
                do {
                    try await stream.startCapture()
                    print("ScreenCaptureKit stream started successfully")
                    self.screenCaptureStream = stream as Any
                    self.systemAudioCallback = callback
                } catch {
                    print("Failed to start ScreenCaptureKit stream: \(error)")
                    print("Please grant screen recording permission in System Settings > Privacy & Security > Screen Recording")
                    legacyCallback()
                }
                
            } catch {
                print("ScreenCaptureKit error: \(error)")
                print("Please grant screen recording permission in System Settings > Privacy & Security > Screen Recording")
                legacyCallback()
            }
        }
        
        return true
    }
    
    @available(macOS 13.0, *)
    private class StreamDelegate: NSObject, SCStreamDelegate {
        func stream(_ stream: SCStream, didStopWithError error: Error) {
            print("ScreenCaptureKit stream stopped with error: \(error)")
        }
    }
    
    @available(macOS 13.0, *)
    private class AudioStreamOutput: NSObject, SCStreamOutput {
        private let callback: (Data) -> Void
        
        init(callback: @escaping (Data) -> Void) {
            self.callback = callback
        }
        
        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .audio else { return }
            processAudioSample(sampleBuffer)
        }
        
        private func processAudioSample(_ sample: CMSampleBuffer) {
            // Extract audio format information
            guard let formatDescription = CMSampleBufferGetFormatDescription(sample) else {
                print("ScreenCaptureKit: No format description")
                return
            }
            
            guard let audioFormatList = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
                print("ScreenCaptureKit: No audio format list")
                return
            }
            
            let audioFormat = audioFormatList.pointee
            let sampleRate = audioFormat.mSampleRate
            let channels = audioFormat.mChannelsPerFrame
            let bitsPerChannel = audioFormat.mBitsPerChannel
            let bytesPerFrame = audioFormat.mBytesPerFrame
            let frameCount = Int(CMSampleBufferGetNumSamples(sample))
            
            // Get audio data from CMSampleBuffer using Core Audio functions
            var audioBufferList = AudioBufferList()
            var status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sample,
                at: 0,
                frameCount: Int32(frameCount),
                into: &audioBufferList
            )
            
            if status != noErr {
                print("ScreenCaptureKit: Failed to copy PCM data, status: \(status)")
                // Fallback: try direct buffer access
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sample) else {
                    print("ScreenCaptureKit: No data buffer")
                    return
                }
                
                var dataPointer: UnsafeMutablePointer<Int8>?
                var length: Int = 0
                
                status = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: nil,
                    totalLengthOut: &length,
                    dataPointerOut: &dataPointer
                )
                
                guard status == noErr, let pointer = dataPointer, length > 0 else {
                    print("ScreenCaptureKit: Failed to get data pointer")
                    return
                }
                
                // Use raw data directly
                let audioData = Data(bytes: pointer, count: length)
                callback(audioData)
                return
            }
            
            // Extract audio data from AudioBufferList
            let numBuffers = Int(audioBufferList.mNumberBuffers)
            guard numBuffers > 0 else {
                print("ScreenCaptureKit: No audio buffers")
                return
            }
            
            let buffer = audioBufferList.mBuffers
            guard let bufferData = buffer.mData, buffer.mDataByteSize > 0 else {
                print("ScreenCaptureKit: Empty audio buffer")
                return
            }
            
            let dataSize = Int(buffer.mDataByteSize)
            print("ScreenCaptureKit: \(sampleRate)Hz, \(channels)ch, \(bitsPerChannel)bit, \(frameCount) frames, \(dataSize) bytes")
            
            // Check if data is all zeros
            let bytePointer = bufferData.assumingMemoryBound(to: UInt8.self)
            let hasNonZero = (0..<min(dataSize, 100)).contains { 
                bytePointer[$0] != 0 
            }
            if !hasNonZero {
                print("ScreenCaptureKit: WARNING - First 100 bytes are all zeros")
            }
            
            // Determine source format
            let isFloat = bitsPerChannel == 32
            let commonFormat: AVAudioCommonFormat = isFloat ? .pcmFormatFloat32 : .pcmFormatInt16
            
            guard let sourceFormat = AVAudioFormat(
                commonFormat: commonFormat,
                sampleRate: Double(sampleRate),
                channels: AVAudioChannelCount(channels),
                interleaved: bytesPerFrame > (bitsPerChannel / 8)  // Interleaved if bytesPerFrame > bytesPerSample
            ) else {
                print("ScreenCaptureKit: Failed to create source format")
                // Use raw data as fallback
                let audioData = Data(bytes: bufferData, count: dataSize)
                callback(audioData)
                return
            }
            
            // Create destination format (16-bit PCM, 44.1kHz, stereo, interleaved)
            guard let destinationFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 44100,
                channels: 2,
                interleaved: true
            ) else {
                print("ScreenCaptureKit: Failed to create destination format")
                // Use raw data as fallback
                let audioData = Data(bytes: bufferData, count: dataSize)
                callback(audioData)
                return
            }
            
            // Create input buffer
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
                print("ScreenCaptureKit: Failed to create input buffer")
                // Use raw data as fallback
                let audioData = Data(bytes: bufferData, count: dataSize)
                callback(audioData)
                return
            }
            
            inputBuffer.frameLength = AVAudioFrameCount(frameCount)
            
            // Copy data to input buffer
            if sourceFormat.isInterleaved {
                // Interleaved - copy directly
                let mutableBufferList = inputBuffer.mutableAudioBufferList
                let mutableBuffer = mutableBufferList.pointee.mBuffers
                if let mutableData = mutableBuffer.mData {
                    mutableData.copyMemory(from: bufferData, byteCount: dataSize)
                    // Note: mDataByteSize is set automatically by the buffer
                }
            } else {
                // Non-interleaved - de-interleave
                if isFloat, let channelData = inputBuffer.floatChannelData {
                    let floatPointer = bufferData.withMemoryRebound(to: Float.self, capacity: dataSize / MemoryLayout<Float>.size) { $0 }
                    let samplesPerChannel = frameCount
                    for channel in 0..<Int(channels) {
                        let channelBuffer = channelData[channel]
                        for frame in 0..<samplesPerChannel {
                            channelBuffer[frame] = floatPointer[frame * Int(channels) + channel]
                        }
                    }
                } else if !isFloat, let channelData = inputBuffer.int16ChannelData {
                    let int16Pointer = bufferData.withMemoryRebound(to: Int16.self, capacity: dataSize / MemoryLayout<Int16>.size) { $0 }
                    let samplesPerChannel = frameCount
                    for channel in 0..<Int(channels) {
                        let channelBuffer = channelData[channel]
                        for frame in 0..<samplesPerChannel {
                            channelBuffer[frame] = int16Pointer[frame * Int(channels) + channel]
                        }
                    }
                }
            }
            
            // Convert to destination format if needed
            if sourceFormat.sampleRate != destinationFormat.sampleRate || 
               sourceFormat.channelCount != destinationFormat.channelCount ||
               sourceFormat.commonFormat != destinationFormat.commonFormat {
                
                guard let converter = AVAudioConverter(from: sourceFormat, to: destinationFormat) else {
                    print("ScreenCaptureKit: Failed to create converter, using raw data")
                    let audioData = Data(bytes: bufferData, count: dataSize)
                    callback(audioData)
                    return
                }
                
                let outputBuffer = AVAudioPCMBuffer(pcmFormat: destinationFormat, frameCapacity: AVAudioFrameCount(frameCount))!
                
                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return inputBuffer
                }
                
                let conversionStatus = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
                
                if conversionStatus == .haveData {
                    // Extract interleaved data from output buffer
                    let outputBufferList = outputBuffer.audioBufferList
                    let outputBuffer = outputBufferList.pointee.mBuffers
                    if let outputData = outputBuffer.mData {
                        let outputSize = Int(outputBuffer.mDataByteSize)
                        let audioData = Data(bytes: outputData, count: outputSize)
                        
                        // Check for non-zero data
                        let hasNonZero = audioData.prefix(100).contains { $0 != 0 }
                        if !hasNonZero {
                            print("ScreenCaptureKit: WARNING - Converted audio is all zeros")
                        } else {
                            print("ScreenCaptureKit: Successfully converted \(outputSize) bytes")
                        }
                        
                        callback(audioData)
                    }
                } else if let error = error {
                    print("ScreenCaptureKit: Conversion error: \(error), using raw data")
                    let audioData = Data(bytes: bufferData, count: dataSize)
                    callback(audioData)
                }
            } else {
                // Format matches, use data directly
                let audioData = Data(bytes: bufferData, count: dataSize)
                callback(audioData)
            }
        }
    }
    
    private func startSystemAudioCaptureLegacy(callback: @escaping (Data) -> Void) -> Bool {
        // Note: True system audio loopback on macOS requires ScreenCaptureKit (macOS 13+)
        // or a virtual audio driver like BlackHole
        // This implementation captures from available audio sources
        // WARNING: inputNode on macOS only captures microphone, not system audio!
        // For system audio, you need to install BlackHole and route audio through it
        
        systemAudioEngine = AVAudioEngine()
        guard let engine = systemAudioEngine else { return false }
        
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        
        print("System audio capture format: \(format.sampleRate)Hz, \(format.channelCount) channels")
        
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
            guard let self = self else { return }
            
            // Check if we have actual audio data
            guard buffer.frameLength > 0 else { return }
            
            // Use raw buffer data directly - convert format if needed
            let audioBufferList = buffer.audioBufferList.pointee
            let numBuffers = Int(audioBufferList.mNumberBuffers)
            
            if numBuffers > 0 {
                let firstBuffer = audioBufferList.mBuffers
                if let audioData = firstBuffer.mData {
                    let bytesPerFrame = Int(format.channelCount) * Int(format.streamDescription.pointee.mBytesPerFrame)
                    let dataSize = Int(buffer.frameLength) * bytesPerFrame
                    let data = Data(bytes: audioData, count: dataSize)
                    
                    // Convert to desired format if needed
                    if format.sampleRate != self.sampleRate || format.channelCount != self.channels {
                        // Need conversion - use converter
                        if let converter = converter, let desiredFormat = desiredFormat {
                            let outputBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat, frameCapacity: buffer.frameLength)!
                            
                            var error: NSError?
                            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                                outStatus.pointee = .haveData
                                return buffer
                            }
                            
                            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
                            
                            if status == .haveData, let outBuffer = outputBuffer.audioBufferList.pointee.mBuffers.mData {
                                let frameCount = Int(outputBuffer.frameLength)
                                let channelCount = Int(desiredFormat.channelCount)
                                let bytesPerFrame = 2 // 16-bit
                                let convertedSize = frameCount * channelCount * bytesPerFrame
                                let convertedData = Data(bytes: outBuffer, count: convertedSize)
                                
                                if convertedSize > 0 {
                                    self.systemAudioCallback?(convertedData)
                                }
                            } else if let error = error {
                                print("Audio conversion error: \(error)")
                            }
                        } else {
                            // No converter available, use raw data
                            if dataSize > 0 {
                                self.systemAudioCallback?(data)
                            }
                        }
                    } else {
                        // Format matches, use data directly
                        if dataSize > 0 {
                            // Debug: Check for non-zero data
                            let hasNonZero = data.withUnsafeBytes { bytes in
                                bytes.contains { $0 != 0 }
                            }
                            if !hasNonZero {
                                print("Warning: System audio buffer contains only zeros")
                            }
                            self.systemAudioCallback?(data)
                        }
                    }
                }
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
        if #available(macOS 13.0, *) {
            if let stream = screenCaptureStream as? SCStream {
                stream.stopCapture { error in
                    if let error = error {
                        print("Error stopping ScreenCaptureKit stream: \(error)")
                    }
                }
                screenCaptureStream = nil
            }
            screenCaptureContentFilter = nil
        }
        
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
        
        print("Microphone capture format: \(format.sampleRate)Hz, \(format.channelCount) channels")
        
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
            guard let self = self else { return }
            
            // Check if we have actual audio data
            guard buffer.frameLength > 0 else { return }
            
            // Use raw buffer data directly - convert format if needed
            let audioBufferList = buffer.audioBufferList.pointee
            let numBuffers = Int(audioBufferList.mNumberBuffers)
            
            if numBuffers > 0 {
                let firstBuffer = audioBufferList.mBuffers
                if let audioData = firstBuffer.mData {
                    let bytesPerFrame = Int(format.channelCount) * Int(format.streamDescription.pointee.mBytesPerFrame)
                    let dataSize = Int(buffer.frameLength) * bytesPerFrame
                    let data = Data(bytes: audioData, count: dataSize)
                    
                    // Convert to desired format if needed
                    if format.sampleRate != self.sampleRate || format.channelCount != self.channels {
                        // Need conversion - use converter
                        if let converter = converter, let desiredFormat = desiredFormat {
                            let outputBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat, frameCapacity: buffer.frameLength)!
                            
                            var error: NSError?
                            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                                outStatus.pointee = .haveData
                                return buffer
                            }
                            
                            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
                            
                            if status == .haveData, let outBuffer = outputBuffer.audioBufferList.pointee.mBuffers.mData {
                                let frameCount = Int(outputBuffer.frameLength)
                                let channelCount = Int(desiredFormat.channelCount)
                                let bytesPerFrame = 2 // 16-bit
                                let convertedSize = frameCount * channelCount * bytesPerFrame
                                let convertedData = Data(bytes: outBuffer, count: convertedSize)
                                
                                if convertedSize > 0 {
                                    self.microphoneCallback?(convertedData)
                                }
                            } else if let error = error {
                                print("Audio conversion error: \(error)")
                            }
                        } else {
                            // No converter available, use raw data
                            if dataSize > 0 {
                                self.microphoneCallback?(data)
                            }
                        }
                    } else {
                        // Format matches, use data directly
                        if dataSize > 0 {
                            // Debug: Check for non-zero data
                            let hasNonZero = data.withUnsafeBytes { bytes in
                                bytes.contains { $0 != 0 }
                            }
                            if !hasNonZero {
                                print("Warning: Microphone buffer contains only zeros")
                            }
                            self.microphoneCallback?(data)
                        }
                    }
                }
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

