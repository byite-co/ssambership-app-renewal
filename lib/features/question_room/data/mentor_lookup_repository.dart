import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';

/// 멘토 공개 표시 정보(표시명만). 계약 수렴 후 정본 소스는
/// `api_web_v1.mentor_directory_v1` 뷰다(anon+authenticated SELECT).
/// ★ 구 RPC `mentor_user_public_v2` 는 앱 권한이 REVOKE 됐다 — 호출 코드를
///   남기지 않는다. 뷰에는 full_name 이 없다(표시명은 nickname 뿐).
class MentorPublic {
  const MentorPublic({required this.id, this.nickname});

  final String id;
  final String? nickname;

  /// 화면 표시명(nickname 트림 비어 있지 않으면 그 값, 아니면 폴백 '멘토').
  String get displayName {
    final String n = nickname?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return '멘토';
  }

  factory MentorPublic.fromMap(Map<String, dynamic> map) {
    return MentorPublic(
      id: map['mentor_id'] as String,
      nickname: map['nickname'] as String?,
    );
  }
}

/// 멘토 공개정보 조회 레포지토리(질문방 상대 표시용).
class MentorLookupRepository {
  const MentorLookupRepository();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  /// 멘토 1명 공개정보 — 뷰 단건 조회. 행이 없으면 null(비공개 멘토 —
  /// 오류가 아니라 중립 표시 '멘토' 폴백 대상이다).
  Future<MentorPublic?> fetch(String mentorId) async {
    final Map<String, dynamic>? row = await _client
        .schema('api_web_v1')
        .from('mentor_directory_v1')
        .select('mentor_id, nickname')
        .eq('mentor_id', mentorId)
        .maybeSingle();
    if (row == null) return null;
    return MentorPublic.fromMap(row);
  }

  /// 여러 멘토를 한 번에(개별 단건 조회). id → MentorPublic.
  /// 뷰에 없는(비공개) 멘토는 결과에서 빠진다 — 호출부가 중립 표시로 폴백.
  Future<Map<String, MentorPublic>> fetchMany(Iterable<String> ids) async {
    final Map<String, MentorPublic> out = <String, MentorPublic>{};
    for (final String id in ids.toSet()) {
      final MentorPublic? m = await fetch(id);
      if (m != null) out[id] = m;
    }
    return out;
  }
}
