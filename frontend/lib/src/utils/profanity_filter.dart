/// 욕설 및 비속어 필터링 유틸리티
class ProfanityFilter {
  // 비속어 리스트 (핵심 단어 위주)
  static const List<String> _badWords = [
    // 기본 욕설
    '앙기기',
    '씨발',
    '씨부랄',
    '씨발랄',
    '시발',
    '시부럴',
    '시부랄',
    '시발럼',
    'ㅅㅂ',
    '개새끼',
    '개년',
    '개새',
    '개쉐',
    '개쉑',
    '좆',
    '좃',
    '좆같',
    '좃나',
    '좃되',
    '보지',
    '자지',
    '쟈지',
    '뷰지',
    '뷰짓',
    '애미',
    '새끼',
    '새키',
    '새퀴',
    '년',
    '놈',
    '자식',
    '호로',
    '호로새끼',
    '호로자식',
    // 병신 관련
    '병신',
    '빙신',
    // 섹스 관련
    '섹스',
    '섹쓰',
    '섹쑤',
    '성교',
    '성행위',
    '성관계',
    '야동',
    '야사',
    '포르노',
    'porn',
    'porno',
    // 기타 비속어
    '미친',
    '지랄',
    '개소리',
    '개지랄',
    '닥쳐',
    '닥치고',
    '죽어',
    '죽어라',
    '죽어버려',
    '뒤져',
    '뒤져라',
    '뒤지고',
    '엿먹어',
    '엿먹어라',
    '엿먹고',
    '엿',
    '젠장',
    '젠장할',
    '젠장맨',
    '젠장놈',
    '개같',
    '개돼지',
    '돼지새끼',
    '돼지같',
    '쓰레기',
    '쓰레기놈',
    '쓰레기년',
    '쓰레기새끼',
    '인간쓰레기',
    '인간말종',
    '말종',
    '말종놈',
    '말종년',
    '말종새끼',
    '찐따',
  ];

  /// 입력된 텍스트에 비속어가 포함되어 있는지 확인
  /// 
  /// [text] 검사할 텍스트
  /// 
  /// 반환값: true = 비속어 포함, false = 정상
  static bool hasProfanity(String text) {
    if (text.isEmpty) return false;

    // 텍스트 정규화: 공백, 특수문자 제거 후 소문자로 변환
    final normalizedText = text
        .replaceAll(' ', '')
        .replaceAll(RegExp(r'[^\w가-힣]'), '') // 특수문자 제거
        .toLowerCase();

    // 각 비속어가 포함되어 있는지 확인
    for (final badWord in _badWords) {
      final normalizedBadWord = badWord.toLowerCase();
      if (normalizedText.contains(normalizedBadWord)) {
        return true;
      }
    }

    return false;
  }
}

