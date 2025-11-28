#ifndef RUNNER_AUDIO_CAPTURE_HANDLER_H_
#define RUNNER_AUDIO_CAPTURE_HANDLER_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include "audio_capture.h"

class AudioCaptureHandler {
 public:
  AudioCaptureHandler(flutter::FlutterEngine* engine);
  ~AudioCaptureHandler();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void OnAudioData(const uint8_t* data, size_t size, bool isSystemAudio);
  bool ConvertWavToMp3(const std::string& wavPath, const std::string& mp3Path);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<AudioCapture> audio_capture_;
  flutter::FlutterEngine* engine_;
};

#endif  // RUNNER_AUDIO_CAPTURE_HANDLER_H_

