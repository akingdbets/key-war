# FCM 백그라운드 알림 설정 가이드

## 구현 완료된 내용

1. ✅ `firebase_messaging` 패키지 추가
2. ✅ FCM 초기화 및 백그라운드 핸들러 설정
3. ✅ FCM 토큰을 Firestore에 자동 저장
4. ✅ 알림 생성 시 FCM 푸시 알림 요청 데이터 저장
5. ✅ Android 설정 완료

## Cloud Functions 설정 (필수)

실제 푸시 알림을 전송하려면 Firebase Cloud Functions를 설정해야 합니다.

### 1. Firebase Functions 프로젝트 초기화

```bash
cd functions
npm install
```

### 2. Cloud Functions 코드 예제

`functions/index.js` 파일을 생성하고 다음 코드를 추가하세요:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// FCM 푸시 알림 전송 함수
exports.sendPushNotification = functions.firestore
  .document('push_notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    
    // 이미 전송된 알림은 무시
    if (data.sent) {
      return null;
    }

    const message = {
      notification: {
        title: data.title,
        body: data.body,
      },
      data: {
        type: data.data.type || '',
        topicId: data.data.topicId || '',
        commentId: data.data.commentId || '',
        notificationId: data.data.notificationId || '',
      },
      token: data.fcmToken,
      android: {
        priority: 'high',
        notification: {
          channelId: 'high_importance_channel',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    try {
      await admin.messaging().send(message);
      console.log('푸시 알림 전송 성공:', context.params.notificationId);
      
      // 전송 완료 표시
      await snap.ref.update({ sent: true, sentAt: admin.firestore.FieldValue.serverTimestamp() });
    } catch (error) {
      console.error('푸시 알림 전송 실패:', error);
      // 실패한 경우 삭제하거나 재시도 로직 추가 가능
    }
  });

// 주기적으로 미전송 알림 재시도 (선택사항)
exports.retryFailedNotifications = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    const unsentNotifications = await admin.firestore()
      .collection('push_notifications')
      .where('sent', '==', false)
      .where('createdAt', '>', new Date(Date.now() - 24 * 60 * 60 * 1000)) // 24시간 이내
      .limit(100)
      .get();

    for (const doc of unsentNotifications.docs) {
      const data = doc.data();
      // 위의 sendPushNotification 로직 재사용
    }
  });
```

### 3. Functions 배포

```bash
firebase deploy --only functions
```

## 테스트 방법

1. 앱을 실행하고 로그인
2. 다른 사용자가 댓글/답글/공감을 남기면:
   - Firestore의 `push_notifications` 컬렉션에 데이터가 생성됨
   - Cloud Functions가 자동으로 FCM 푸시 알림 전송
   - 앱이 백그라운드에 있어도 알림 수신 가능

## 주의사항

- iOS의 경우 APNs 인증서 설정이 필요합니다
- Android 13 이상에서는 알림 권한을 명시적으로 요청해야 합니다 (이미 구현됨)
- Cloud Functions를 사용하지 않으면 푸시 알림이 전송되지 않습니다

## 대안: 서버리스 없이 테스트

Cloud Functions 없이 테스트하려면:
1. Firebase Console에서 직접 FCM 테스트 메시지 전송
2. 또는 별도의 Node.js 서버에서 FCM Admin SDK 사용


