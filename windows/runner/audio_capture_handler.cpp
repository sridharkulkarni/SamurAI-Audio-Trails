#include "audio_capture_handler.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <windows.h>
#include <processthreadsapi.h>

AudioCaptureHandler::AudioCaptureHandler(flutter::FlutterEngine* engine)
    : engine_(engine) {
  audio_capture_ = std::make_unique<AudioCapture>();
  audio_capture_->Initialize();

  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine_->messenger(), "com.samurai.audio_capture",
      &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        this->HandleMethodCall(call, std::move(result));
      });
}

AudioCaptureHandler::~AudioCaptureHandler() {
  if (audio_capture_) {
    audio_capture_->StopSystemAudioCapture();
    audio_capture_->StopMicrophoneCapture();
  }
}

void AudioCaptureHandler::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method_name = method_call.method_name();

  if (method_name == "getInputDevices") {
    auto devices = audio_capture_->GetInputDevices();
    flutter::EncodableList device_list;
    for (const auto& device : devices) {
      flutter::EncodableMap device_map;
      device_map[flutter::EncodableValue("id")] = flutter::EncodableValue(device.id);
      device_map[flutter::EncodableValue("name")] = flutter::EncodableValue(device.name);
      device_map[flutter::EncodableValue("isInput")] = flutter::EncodableValue(device.isInput);
      device_list.push_back(flutter::EncodableValue(device_map));
    }
    result->Success(flutter::EncodableValue(device_list));
  } else if (method_name == "getOutputDevices") {
    auto devices = audio_capture_->GetOutputDevices();
    flutter::EncodableList device_list;
    for (const auto& device : devices) {
      flutter::EncodableMap device_map;
      device_map[flutter::EncodableValue("id")] = flutter::EncodableValue(device.id);
      device_map[flutter::EncodableValue("name")] = flutter::EncodableValue(device.name);
      device_map[flutter::EncodableValue("isInput")] = flutter::EncodableValue(device.isInput);
      device_list.push_back(flutter::EncodableValue(device_map));
    }
    result->Success(flutter::EncodableValue(device_list));
  } else if (method_name == "startSystemAudioCapture") {
    std::string deviceId = "";
    if (method_call.arguments() && method_call.arguments()->IsMap()) {
      const auto& args = std::get<flutter::EncodableMap>(*method_call.arguments());
      auto it = args.find(flutter::EncodableValue("deviceId"));
      if (it != args.end()) {
        deviceId = std::get<std::string>(it->second);
      }
    }

    bool success = audio_capture_->StartSystemAudioCapture(
        deviceId,
        [this](const uint8_t* data, size_t size) {
          this->OnAudioData(data, size, true);
        });

    if (success) {
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("FAILED", "Failed to start system audio capture");
    }
  } else if (method_name == "stopSystemAudioCapture") {
    audio_capture_->StopSystemAudioCapture();
    result->Success(flutter::EncodableValue(true));
  } else if (method_name == "startMicrophoneCapture") {
    std::string deviceId = "";
    if (method_call.arguments() && method_call.arguments()->IsMap()) {
      const auto& args = std::get<flutter::EncodableMap>(*method_call.arguments());
      auto it = args.find(flutter::EncodableValue("deviceId"));
      if (it != args.end()) {
        deviceId = std::get<std::string>(it->second);
      }
    }

    bool success = audio_capture_->StartMicrophoneCapture(
        deviceId,
        [this](const uint8_t* data, size_t size) {
          this->OnAudioData(data, size, false);
        });

    if (success) {
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("FAILED", "Failed to start microphone capture");
    }
  } else if (method_name == "stopMicrophoneCapture") {
    audio_capture_->StopMicrophoneCapture();
    result->Success(flutter::EncodableValue(true));
  } else if (method_name == "convertToMp3") {
    std::string wavPath = "";
    std::string mp3Path = "";
    
    if (method_call.arguments() && method_call.arguments()->IsMap()) {
      const auto& args = std::get<flutter::EncodableMap>(*method_call.arguments());
      auto wavIt = args.find(flutter::EncodableValue("wavPath"));
      auto mp3It = args.find(flutter::EncodableValue("mp3Path"));
      
      if (wavIt != args.end()) {
        wavPath = std::get<std::string>(wavIt->second);
      }
      if (mp3It != args.end()) {
        mp3Path = std::get<std::string>(mp3It->second);
      }
    }
    
    if (wavPath.empty() || mp3Path.empty()) {
      result->Error("INVALID_ARGS", "wavPath and mp3Path are required");
      return;
    }
    
    bool success = ConvertWavToMp3(wavPath, mp3Path);
    result->Success(flutter::EncodableValue(success));
  } else {
    result->NotImplemented();
  }
}

void AudioCaptureHandler::OnAudioData(const uint8_t* data, size_t size, bool isSystemAudio) {
  // Convert to base64
  const char base64_chars[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  
  std::string base64;
  base64.reserve(((size + 2) / 3) * 4);
  
  for (size_t i = 0; i < size; i += 3) {
    uint32_t octet_a = i < size ? data[i] : 0;
    uint32_t octet_b = i + 1 < size ? data[i + 1] : 0;
    uint32_t octet_c = i + 2 < size ? data[i + 2] : 0;
    
    uint32_t triple = (octet_a << 16) | (octet_b << 8) | octet_c;
    
    base64 += base64_chars[(triple >> 18) & 0x3F];
    base64 += base64_chars[(triple >> 12) & 0x3F];
    base64 += (i + 1 < size) ? base64_chars[(triple >> 6) & 0x3F] : '=';
    base64 += (i + 2 < size) ? base64_chars[triple & 0x3F] : '=';
  }

  // Print to console
  //std::cout << (isSystemAudio ? "[SYSTEM] " : "[MIC] ") << base64 << std::endl;

  // Also send to Flutter via event channel
  if (method_channel_ && engine_) {
    flutter::EncodableMap event_data;
    event_data[flutter::EncodableValue("type")] = 
        flutter::EncodableValue(isSystemAudio ? "system" : "microphone");
    event_data[flutter::EncodableValue("data")] = flutter::EncodableValue(base64);
    event_data[flutter::EncodableValue("size")] = flutter::EncodableValue(static_cast<int64_t>(size));
    
    method_channel_->InvokeMethod("onAudioData", 
        std::make_unique<flutter::EncodableValue>(event_data));
  }
}

bool AudioCaptureHandler::ConvertWavToMp3(const std::string& wavPath, const std::string& mp3Path) {
  STARTUPINFOA si = { sizeof(si) };
  PROCESS_INFORMATION pi;
  ZeroMemory(&si, sizeof(si));
  ZeroMemory(&pi, sizeof(pi));
  
  // Build command: ffmpeg -i input.wav -codec:a libmp3lame -b:a 192k -y output.mp3
  std::string cmd = "ffmpeg -i \"" + wavPath + "\" -codec:a libmp3lame -b:a 192k -y \"" + mp3Path + "\"";
  
  // Create process
  BOOL success = CreateProcessA(
    NULL,                    // Application name
    const_cast<char*>(cmd.c_str()),  // Command line
    NULL,                    // Process security attributes
    NULL,                    // Thread security attributes
    FALSE,                   // Inherit handles
    CREATE_NO_WINDOW,        // Creation flags
    NULL,                    // Environment
    NULL,                    // Current directory
    &si,                     // Startup info
    &pi                      // Process information
  );
  
  if (!success) {
    return false;
  }
  
  // Wait for process to complete
  WaitForSingleObject(pi.hProcess, INFINITE);
  
  DWORD exitCode;
  GetExitCodeProcess(pi.hProcess, &exitCode);
  
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  
  return exitCode == 0;
}

