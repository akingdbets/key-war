# ADB 설치 오류 해결 방법

## 문제
```
INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.naisu.keywar signatures do not match newer version
```

이 오류는 기존에 설치된 앱과 현재 빌드의 서명이 다를 때 발생합니다.

## 해결 방법

### 방법 1: 기존 앱 제거 후 재설치 (권장)

```bash
# 기존 앱 제거
adb uninstall com.naisu.keywar

# 앱 재설치
flutter run
```

또는 Android Studio에서:
1. 디바이스에서 앱을 수동으로 제거
2. 다시 실행

### 방법 2: Flutter Clean 후 재빌드

```bash
cd frontend
flutter clean
flutter pub get
flutter run
```

### 방법 3: 디바이스에서 직접 제거

1. 디바이스 설정 → 앱 → Key War 찾기
2. 앱 제거
3. 다시 `flutter run` 실행

## 참고

- 디버그 빌드와 릴리즈 빌드의 서명이 다를 수 있습니다
- 다른 컴퓨터에서 빌드한 앱을 설치하려고 할 때도 발생할 수 있습니다
- 개발 중에는 디버그 키스토어를 사용하므로, 같은 디바이스에서 계속 개발하는 경우 문제없습니다

