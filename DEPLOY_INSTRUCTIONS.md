# Cloud Functions 배포 방법

## 문제
PowerShell에서 `firebase deploy` 명령이 작동하지 않습니다.

## 해결 방법

### 방법 1: Firebase Console에서 배포
1. Firebase Console (https://console.firebase.google.com) 접속
2. 프로젝트 선택
3. Functions 메뉴로 이동
4. `sendPushNotification` 함수를 찾아서 "재배포" 클릭

### 방법 2: CMD에서 배포
PowerShell 대신 CMD를 사용:
```cmd
cd C:\Users\xnaud\Desktop\keyboard-arena
npx firebase deploy --only functions
```

### 방법 3: Git Bash에서 배포
Git Bash를 사용:
```bash
cd /c/Users/xnaud/Desktop/keyboard-arena
npx firebase deploy --only functions
```

## 수정된 내용
- `functions/index.js`에 상세한 로깅 추가
- FCM 토큰 검증 강화
- 에러 처리 개선

## 테스트 방법
1. 앱에서 다른 사용자로 댓글/답글/공감 남기기
2. Firebase Console → Functions → 로그 확인
3. "📨 푸시 알림 요청 수신" 로그 확인
4. "✅ 푸시 알림 전송 성공" 또는 "❌ 전송 실패" 로그 확인


