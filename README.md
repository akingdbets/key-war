# 🔥 KEY WAR (키워)

**입으로만 싸우지 말고, 손가락으로 증명하라.**
Flutter와 Firebase로 제작된 실시간 투표 및 토론 플랫폼입니다.

---

## 🛠 개발 환경 설정 (Getting Started)

이 프로젝트는 보안상의 이유로 **Firebase 설정 파일**과 **자동 생성된 코드**가 Git에 포함되어 있지 않습니다.
처음 프로젝트를 실행하려면 아래 단계를 순서대로 진행해야 합니다.

### 1. 필수 요구 사항 (Prerequisites)
* Flutter SDK (3.x 이상)
* Dart SDK
* Firebase CLI
* Node.js (Firebase CLI 실행용)

### 2. 프로젝트 클론 및 패키지 설치
```bash
# 1. 프로젝트 다운로드
git clone [레포지토리 주소]

# 2. 프로젝트 폴더로 이동
cd key-war

# 3. Flutter 패키지 설치
flutter pub get

# 1. Firebase 로그인 (이미 되어있다면 생략)
firebase login

# 2. FlutterFire CLI 활성화
dart pub global activate flutterfire_cli

# 3. 설정 파일 자동 생성
flutterfire configure
# (화면 지시에 따라 'keyboard-arena' 프로젝트 선택 -> Android/iOS 선택)

# 자동 생성 코드 빌드 (Code Generation)
flutter pub run build_runner build --delete-conflicting-outputs

# 디버그 모드로 실행
flutter run