#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // ช่อง "noir/window" ให้ฝั่ง Dart สั่งเต็มจอ (F11)
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;

  // เต็มจอไร้ขอบ: จำสไตล์/ตำแหน่งเดิมไว้คืนตอนออก
  void SetFullscreen(bool on);
  bool fullscreen_ = false;
  LONG saved_style_ = 0;
  RECT saved_rect_ = {};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
