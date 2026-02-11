# 기존 함수 삭제 방법

## 문제
기존 v1 함수와 새 v2 함수가 충돌하여 배포가 실패합니다.

## 해결 방법

### 방법 1: Firebase Console에서 삭제
1. Firebase Console (https://console.firebase.google.com) 접속
2. 프로젝트 선택
3. Functions 메뉴로 이동
4. `sendPushNotification` 함수 찾기
5. 함수 옆의 "..." 메뉴 클릭
6. "삭제" 선택

### 방법 2: 명령어로 삭제 (대화형 모드)
```cmd
cd C:\Users\xnaud\Desktop\keyboard-arena
npx firebase functions:delete sendPushNotification --region us-central1
```
프롬프트에서 `y` 입력

### 방법 3: 새 함수 이름 사용
함수 이름을 변경하여 새로 배포 (현재 코드는 이미 수정됨)

## 삭제 후 배포
```cmd
cd C:\Users\xnaud\Desktop\keyboard-arena
npx firebase deploy --only functions
```


