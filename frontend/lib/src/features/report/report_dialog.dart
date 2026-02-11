import 'package:flutter/material.dart';

/// 신고 사유 선택 다이얼로그
class ReportDialog extends StatelessWidget {
  const ReportDialog({super.key});

  /// 다이얼로그 표시 및 선택된 사유 반환
  static Future<String?> show(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (context) => const ReportDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardBgColor = isDark ? const Color(0xFF2D2D3A) : Colors.white;
    final borderColor = isDark ? Colors.white12 : Colors.grey[300]!;

    // 신고 사유 목록
    final reasons = [
      '욕설 및 비하 발언',
      '상업적 광고 및 스팸',
      '음란물 및 불건전한 내용',
      '불법 정보 및 선동',
      '불건전한 닉네임',
      '기타',
    ];

    return AlertDialog(
      backgroundColor: cardBgColor,
      title: Text(
        '신고 사유 선택',
        style: TextStyle(color: textColor),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: reasons.length,
          itemBuilder: (context, index) {
            final reason = reasons[index];
            return InkWell(
              onTap: () => Navigator.pop(context, reason),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2C) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      color: Colors.red[400],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '취소',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }
}

