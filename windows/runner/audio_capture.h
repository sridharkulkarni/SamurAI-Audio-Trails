#ifndef RUNNER_AUDIO_CAPTURE_H_
#define RUNNER_AUDIO_CAPTURE_H_

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <string>
#include <vector>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>
#include <atomic>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

struct AudioDevice {
  std::string id;
  std::string name;
  bool isInput;
};

class AudioCapture {
 public:
  AudioCapture();
  ~AudioCapture();

  // Initialize COM and audio system
  bool Initialize();

  // Get list of audio devices
  std::vector<AudioDevice> GetInputDevices();
  std::vector<AudioDevice> GetOutputDevices();

  // Start capturing system audio (loopback)
  bool StartSystemAudioCapture(const std::string& deviceId,
                                std::function<void(const uint8_t*, size_t)> callback);

  // Start capturing microphone
  bool StartMicrophoneCapture(const std::string& deviceId,
                               std::function<void(const uint8_t*, size_t)> callback);

  // Stop capturing
  void StopSystemAudioCapture();
  void StopMicrophoneCapture();

  // Check if capturing
  bool IsSystemAudioCapturing() const { return system_audio_capturing_; }
  bool IsMicrophoneCapturing() const { return microphone_capturing_; }

 private:
  bool EnumerateDevices(bool input, std::vector<AudioDevice>& devices);
  bool StartCapture(bool loopback, const std::string& deviceId,
                    std::function<void(const uint8_t*, size_t)> callback,
                    std::atomic<bool>& capturing_flag);
  void CaptureThread(bool loopback, const std::string& deviceId,
                     std::function<void(const uint8_t*, size_t)> callback,
                     std::atomic<bool>& capturing_flag);

  IMMDeviceEnumerator* device_enumerator_;
  std::mutex capture_mutex_;
  std::thread system_audio_thread_;
  std::thread microphone_thread_;
  std::atomic<bool> system_audio_capturing_;
  std::atomic<bool> microphone_capturing_;
  std::atomic<bool> should_stop_;
};

#endif  // RUNNER_AUDIO_CAPTURE_H_

