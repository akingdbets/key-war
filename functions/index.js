const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
admin.initializeApp();

// FCM 푸시 알림 전송 함수 (v2)
exports.sendPushNotification = onDocumentCreated(
  {
    document: 'push_notifications/{notificationId}',
    region: 'asia-northeast3',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      console.error('❌ 문서 데이터가 없습니다.');
      return;
    }

    const data = snap.data();
    const notificationId = event.params.notificationId;
    
    console.log('📨 푸시 알림 요청 수신:', notificationId);
    console.log('📋 데이터:', JSON.stringify(data, null, 2));
    
    // 이미 전송된 알림은 무시
    if (data.sent) {
      console.log('⏭️ 이미 전송된 알림입니다.');
      return;
    }

    // FCM 토큰 확인
    const fcmToken = data.fcmToken;
    if (!fcmToken || typeof fcmToken !== 'string' || fcmToken.trim() === '') {
      console.error('❌ 전송 실패: 토큰이 없습니다.');
      console.error('❌ 데이터:', JSON.stringify(data, null, 2));
      // 실패한 알림 표시
      await snap.ref.update({ 
        sent: false, 
        error: 'FCM token is missing or invalid',
        failedAt: admin.firestore.FieldValue.serverTimestamp() 
      });
      return;
    }

    const message = {
      notification: {
        title: data.title || '알림',
        body: data.body || '',
      },
      data: {
        type: data.data?.type || '',
        topicId: data.data?.topicId || '',
        commentId: data.data?.commentId || '',
        notificationId: data.data?.notificationId || '',
      },
      token: fcmToken,
      android: {
        priority: 'high',
        notification: {
          channelId: 'high_importance_channel',
          sound: 'default',
          icon: 'ic_notification', // 알림 아이콘 (drawable 리소스 이름, AndroidManifest.xml의 default_notification_icon과 일치)
          color: '#000000', // 알림 색상 (선택사항)
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
      console.log('📤 FCM 메시지 전송 시도:', {
        token: fcmToken.substring(0, 20) + '...',
        title: message.notification.title,
        body: message.notification.body,
      });
      
      const response = await admin.messaging().send(message);
      console.log('✅ 푸시 알림 전송 성공:', notificationId, 'Message ID:', response);
      
      // 전송 완료 표시
      await snap.ref.update({ 
        sent: true, 
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        messageId: response 
      });
    } catch (error) {
      console.error('❌ 푸시 알림 전송 실패:', error);
      console.error('❌ 에러 상세:', {
        code: error.code,
        message: error.message,
        stack: error.stack
      });
      
      // 실패한 알림 표시
      await snap.ref.update({ 
        sent: false, 
        error: error.message || error.toString(),
        failedAt: admin.firestore.FieldValue.serverTimestamp() 
      });
    }
  }
);

// 주기적으로 미전송 알림 재시도 (선택사항 - 주석 처리)
// exports.retryFailedNotifications = functions.pubsub
//   .schedule('every 5 minutes')
//   .onRun(async (context) => {
//     const unsentNotifications = await admin.firestore()
//       .collection('push_notifications')
//       .where('sent', '==', false)
//       .where('createdAt', '>', new Date(Date.now() - 24 * 60 * 60 * 1000)) // 24시간 이내
//       .limit(100)
//       .get();

//     for (const doc of unsentNotifications.docs) {
//       const data = doc.data();
//       // 위의 sendPushNotification 로직 재사용
//     }
//   });