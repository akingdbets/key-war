import 'package:flutter/material.dart';

// 앱 전체에서 공유할 테마 설정 변수
// 기본값: ThemeMode.dark (다크모드)
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void toggleTheme() {
  if (themeNotifier.value == ThemeMode.dark) {
    themeNotifier.value = ThemeMode.light;
  } else {
    themeNotifier.value = ThemeMode.dark;
  }
}