#include "audio_capture.h"
#include <iostream>
#include <algorithm>

const CLSID CLSID_MMDeviceEnumerator = __uuidof(MMDeviceEnumerator);
const IID IID_IMMDeviceEnumerator = __uuidof(IMMDeviceEnumerator);

constexpr REFERENCE_TIME REFTIMES_PER_SEC = 10000000;
constexpr REFERENCE_TIME REFTIMES_PER_MILLISEC = 10000;
constexpr UINT32 SAMPLE_RATE = 44100;
constexpr UINT32 CHANNELS = 2;
constexpr UINT32 BITS_PER_SAMPLE = 16;
constexpr UINT32 BLOCK_ALIGN = CHANNELS * BITS_PER_SAMPLE / 8;
constexpr UINT32 BYTES_PER_SECOND = SAMPLE_RATE * BLOCK_ALIGN;

AudioCapture::AudioCapture()
    : device_enumerator_(nullptr),
      system_audio_capturing_(false),
      microphone_capturing_(false),
      should_stop_(false) {
}

AudioCapture::~AudioCapture() {
  StopSystemAudioCapture();
  StopMicrophoneCapture();
  if (device_enumerator_) {
    device_enumerator_->Release();
    device_enumerator_ = nullptr;
  }
}

bool AudioCapture::Initialize() {
  HRESULT hr = CoCreateInstance(
      CLSID_MMDeviceEnumerator, nullptr, CLSCTX_ALL,
      IID_IMMDeviceEnumerator,
      reinterpret_cast<void**>(&device_enumerator_));

  return SUCCEEDED(hr);
}

std::vector<AudioDevice> AudioCapture::GetInputDevices() {
  std::vector<AudioDevice> devices;
  EnumerateDevices(true, devices);
  return devices;
}

std::vector<AudioDevice> AudioCapture::GetOutputDevices() {
  std::vector<AudioDevice> devices;
  EnumerateDevices(false, devices);
  return devices;
}

bool AudioCapture::EnumerateDevices(bool input, std::vector<AudioDevice>& devices) {
  if (!device_enumerator_) {
    return false;
  }

  IMMDeviceCollection* deviceCollection = nullptr;
  HRESULT hr = device_enumerator_->EnumAudioEndpoints(
      input ? eCapture : eRender, DEVICE_STATE_ACTIVE, &deviceCollection);

  if (FAILED(hr)) {
    return false;
  }

  UINT count = 0;
  deviceCollection->GetCount(&count);

  for (UINT i = 0; i < count; i++) {
    IMMDevice* device = nullptr;
    hr = deviceCollection->Item(i, &device);
    if (FAILED(hr)) continue;

    LPWSTR deviceId = nullptr;
    hr = device->GetId(&deviceId);
    if (FAILED(hr)) {
      device->Release();
      continue;
    }

    IPropertyStore* properties = nullptr;
    hr = device->OpenPropertyStore(STGM_READ, &properties);
    if (FAILED(hr)) {
      CoTaskMemFree(deviceId);
      device->Release();
      continue;
    }

    PROPVARIANT friendlyName;
    PropVariantInit(&friendlyName);
    hr = properties->GetValue(PKEY_Device_FriendlyName, &friendlyName);

    AudioDevice audioDevice;
    if (SUCCEEDED(hr) && friendlyName.vt == VT_LPWSTR) {
      // Convert wide string to UTF-8
      int size_needed = WideCharToMultiByte(CP_UTF8, 0, friendlyName.pwszVal, -1, nullptr, 0, nullptr, nullptr);
      std::string name(size_needed, 0);
      WideCharToMultiByte(CP_UTF8, 0, friendlyName.pwszVal, -1, &name[0], size_needed, nullptr, nullptr);
      audioDevice.name = name;
    } else {
      audioDevice.name = "Unknown Device";
    }

    // Convert device ID to UTF-8
    int id_size = WideCharToMultiByte(CP_UTF8, 0, deviceId, -1, nullptr, 0, nullptr, nullptr);
    std::string id(id_size, 0);
    WideCharToMultiByte(CP_UTF8, 0, deviceId, -1, &id[0], id_size, nullptr, nullptr);
    audioDevice.id = id;
    audioDevice.isInput = input;

    devices.push_back(audioDevice);

    PropVariantClear(&friendlyName);
    CoTaskMemFree(deviceId);
    properties->Release();
    device->Release();
  }

  deviceCollection->Release();
  return true;
}

bool AudioCapture::StartSystemAudioCapture(const std::string& deviceId,
                                           std::function<void(const uint8_t*, size_t)> callback) {
  return StartCapture(true, deviceId, callback, system_audio_capturing_);
}

bool AudioCapture::StartMicrophoneCapture(const std::string& deviceId,
                                          std::function<void(const uint8_t*, size_t)> callback) {
  return StartCapture(false, deviceId, callback, microphone_capturing_);
}

bool AudioCapture::StartCapture(bool loopback, const std::string& deviceId,
                                std::function<void(const uint8_t*, size_t)> callback,
                                std::atomic<bool>& capturing_flag) {
  std::lock_guard<std::mutex> lock(capture_mutex_);

  if (capturing_flag.load()) {
    return false;  // Already capturing
  }

  capturing_flag = true;
  should_stop_ = false;

  std::thread capture_thread(&AudioCapture::CaptureThread, this, loopback, deviceId, callback, std::ref(capturing_flag));
  
  if (loopback) {
    system_audio_thread_ = std::move(capture_thread);
  } else {
    microphone_thread_ = std::move(capture_thread);
  }

  return true;
}

void AudioCapture::CaptureThread(bool loopback, const std::string& deviceId,
                                 std::function<void(const uint8_t*, size_t)> callback,
                                 std::atomic<bool>& capturing_flag) {
  IMMDevice* device = nullptr;
  IAudioClient* audioClient = nullptr;
  IAudioCaptureClient* captureClient = nullptr;
  WAVEFORMATEX* pwfx = nullptr;

  HRESULT hr = S_OK;

  // Get device
  if (deviceId.empty()) {
    // Use default device
    hr = device_enumerator_->GetDefaultAudioEndpoint(
        loopback ? eRender : eCapture, eConsole, &device);
  } else {
    // Convert deviceId to wide string
    int wlen = MultiByteToWideChar(CP_UTF8, 0, deviceId.c_str(), -1, nullptr, 0);
    std::vector<wchar_t> wdeviceId(wlen);
    MultiByteToWideChar(CP_UTF8, 0, deviceId.c_str(), -1, wdeviceId.data(), wlen);

    hr = device_enumerator_->GetDevice(wdeviceId.data(), &device);
  }

  if (FAILED(hr) || !device) {
    capturing_flag = false;
    return;
  }

  // Activate audio client
  hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                        reinterpret_cast<void**>(&audioClient));
  if (FAILED(hr)) {
    device->Release();
    capturing_flag = false;
    return;
  }

  // Get mix format
  hr = audioClient->GetMixFormat(&pwfx);
  if (FAILED(hr)) {
    audioClient->Release();
    device->Release();
    capturing_flag = false;
    return;
  }

  // For loopback, we need to use the render endpoint's format
  // For capture, we can set our desired format
  WAVEFORMATEX desiredFormat = {};
  desiredFormat.wFormatTag = WAVE_FORMAT_PCM;
  desiredFormat.nChannels = CHANNELS;
  desiredFormat.nSamplesPerSec = SAMPLE_RATE;
  desiredFormat.wBitsPerSample = BITS_PER_SAMPLE;
  desiredFormat.nBlockAlign = BLOCK_ALIGN;
  desiredFormat.nAvgBytesPerSec = BYTES_PER_SECOND;
  desiredFormat.cbSize = 0;

  WAVEFORMATEX* closestMatch = nullptr;
  if (loopback) {
    // For loopback, use the device's format
    closestMatch = pwfx;
  } else {
    // For capture, try to set our format
    hr = audioClient->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &desiredFormat, &closestMatch);
    if (hr == S_FALSE) {
      // Use closest match
      if (closestMatch) {
        CoTaskMemFree(pwfx);
        pwfx = closestMatch;
      }
    } else if (SUCCEEDED(hr)) {
      CoTaskMemFree(pwfx);
      pwfx = &desiredFormat;
    }
  }

  // Initialize audio client
  REFERENCE_TIME hnsRequestedDuration = REFTIMES_PER_SEC;
  hr = audioClient->Initialize(
      AUDCLNT_SHAREMODE_SHARED,
      loopback ? AUDCLNT_STREAMFLAGS_LOOPBACK : 0,
      hnsRequestedDuration, 0, pwfx, nullptr);

  if (FAILED(hr)) {
    CoTaskMemFree(pwfx);
    audioClient->Release();
    device->Release();
    capturing_flag = false;
    return;
  }

  // Get capture client
  hr = audioClient->GetService(__uuidof(IAudioCaptureClient),
                               reinterpret_cast<void**>(&captureClient));
  if (FAILED(hr)) {
    CoTaskMemFree(pwfx);
    audioClient->Release();
    device->Release();
    capturing_flag = false;
    return;
  }

  // Start capturing
  hr = audioClient->Start();
  if (FAILED(hr)) {
    CoTaskMemFree(pwfx);
    captureClient->Release();
    audioClient->Release();
    device->Release();
    capturing_flag = false;
    return;
  }

  // Capture loop
  UINT32 packetLength = 0;
  BYTE* data = nullptr;
  DWORD flags = 0;

  while (capturing_flag.load() && !should_stop_.load()) {
    hr = captureClient->GetNextPacketSize(&packetLength);

    while (SUCCEEDED(hr) && packetLength > 0) {
      hr = captureClient->GetBuffer(&data, &packetLength, &flags, nullptr, nullptr);

      if (SUCCEEDED(hr)) {
        // Always send data, even if silent (for debugging and to ensure data flow)
        size_t dataSize = packetLength;
        
        // If silent, we still send zeros (this is normal for silence)
        // But we should still process the data
        if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
          // Buffer is silent (all zeros), but we still send it
          // This is normal when no audio is playing
        }
        
        // Call callback with audio data
        if (callback && dataSize > 0) {
          callback(data, dataSize);
        }

        captureClient->ReleaseBuffer(packetLength);
      }

      hr = captureClient->GetNextPacketSize(&packetLength);
    }

    Sleep(10);  // Small sleep to prevent CPU spinning
  }

  // Cleanup
  audioClient->Stop();
  CoTaskMemFree(pwfx);
  captureClient->Release();
  audioClient->Release();
  device->Release();
  capturing_flag = false;
}

void AudioCapture::StopSystemAudioCapture() {
  std::lock_guard<std::mutex> lock(capture_mutex_);
  if (system_audio_capturing_.load()) {
    should_stop_ = true;
    system_audio_capturing_ = false;
    if (system_audio_thread_.joinable()) {
      system_audio_thread_.join();
    }
  }
}

void AudioCapture::StopMicrophoneCapture() {
  std::lock_guard<std::mutex> lock(capture_mutex_);
  if (microphone_capturing_.load()) {
    should_stop_ = true;
    microphone_capturing_ = false;
    if (microphone_thread_.joinable()) {
      microphone_thread_.join();
    }
  }
}

