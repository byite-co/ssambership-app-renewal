import 'package:flutter/material.dart';

import '../../../../design/role_accent.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/primary_button.dart';

/// 신고 사유(라벨=화면 표기, code=저장값). ★ 외부 연락처 유도 신고 동선 포함.
const List<MapEntry<String, String>> reportReasons = <MapEntry<String, String>>[
  MapEntry<String, String>('inappropriate', '부적절한 내용'),
  MapEntry<String, String>('spam', '스팸·광고'),
  MapEntry<String, String>('external_contact', '외부 연락처 유도'),
  MapEntry<String, String>('copyright', '저작권·출처 위반'),
  MapEntry<String, String>('etc', '기타'),
];

/// 게시물 신고 안내 문구(기본).
const String _postGuidance =
    '게시물의 출처·권리는 작성자에게 있어요. 외부 연락처 유도, 저작권·출처 위반,'
    ' 불법·부적절한 정보는 신고해 주세요. 접수 내용은 운영팀이 검토해요.';

/// 신고 시트를 열고 선택한 사유 code 를 반환(취소 시 null — 이때 쓰기 0회).
///
/// [guidance] 는 안내 문구만 바꾼다(사유 목록·저장 계약은 공용 그대로).
/// 질문방의 사용자 신고처럼 대상이 게시물이 아닌 경우에 쓴다.
Future<String?> showReportSheet(BuildContext context, {String? guidance}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: ColorTokens.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (BuildContext ctx) => _ReportSheet(guidance: guidance),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({this.guidance});

  final String? guidance;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = reportReasons.first.key;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('신고하기', style: AppType.title),
            const SizedBox(height: 8),
            // 출처/권리 확인 안내 — 외부 연락처 유도·불법 정보 신고 동선.
            Text(widget.guidance ?? _postGuidance, style: AppType.caption),
            const SizedBox(height: 12),
            for (final MapEntry<String, String> r in reportReasons)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: r.key,
                groupValue: _reason,
                activeColor: AppAccent.of(context).accent,
                onChanged: (String? v) =>
                    setState(() => _reason = v ?? _reason),
                title: Text(r.value, style: AppType.body),
              ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: '신고 접수',
              onPressed: () => Navigator.of(context).pop(_reason),
            ),
          ],
        ),
      ),
    );
  }
}
