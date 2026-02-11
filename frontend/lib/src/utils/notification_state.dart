/// 전역 알림 상태 관리 클래스
/// 현재 사용자가 보고 있는 투표방 ID를 추적하여
/// 해당 방의 알림은 표시하지 않도록 함
class NotificationState {
  /// 현재 사용자가 보고 있는 투표방 ID
  /// null이면 어떤 투표방도 보고 있지 않음을 의미
  static String? currentViewingVoteId;

  /// 현재 보고 있는 투표방 ID 설정
  static void setCurrentViewingVoteId(String? voteId) {
    currentViewingVoteId = voteId;
  }

  /// 현재 보고 있는 투표방 ID 가져오기
  static String? getCurrentViewingVoteId() {
    return currentViewingVoteId;
  }

  /// 특정 투표방을 현재 보고 있는지 확인
  static bool isViewingVote(String? voteId) {
    if (voteId == null || currentViewingVoteId == null) {
      return false;
    }
    return currentViewingVoteId == voteId;
  }
}

