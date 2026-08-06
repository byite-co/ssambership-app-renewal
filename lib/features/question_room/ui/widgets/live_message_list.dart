import 'package:flutter/material.dart';

import '../../../../design/spacing_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../data/attachments/attachment_url_resolver.dart';
import '../../data/models/question_attachment.dart';
import '../../data/models/question_message.dart';
import '../../data/thread_messages_controller.dart';
import '../../data/thread_realtime.dart';
import 'message_bubble.dart';
import 'message_file_attachment.dart';
import 'message_image_attachment.dart';

/// 실시간 메시지 목록. [controller] 를 렌더하고 [realtime] 구독을 시작/정리한다.
///
/// - 실시간 insert → controller.add → 새로고침 없이 즉시 목록에 추가(맨 아래로 스크롤).
/// - 내가 보낸 메시지도 화면(부모)이 같은 controller 에 add 하므로 함께 반영된다(중복 무시).
/// - Realtime 이 꺼져 있으면(publication 미포함) 콜백이 안 올 뿐, 부모의 재조회 폴백으로 동작.
class LiveMessageList extends StatefulWidget {
  const LiveMessageList({
    super.key,
    required this.controller,
    required this.realtime,
    required this.currentUid,
    this.emptyHint = '첫 메시지를 남겨보세요.',
    this.onThreadUpdate,
    this.attachments = const <QuestionAttachment>[],
    this.resolver,
    this.onOpenImage,
    this.onOpenFile,
    this.onAttachmentInsert,
    this.hasEarlier = false,
    this.onLoadEarlier,
  });

  final ThreadMessagesController controller;
  final ThreadRealtimePort realtime;
  final String? currentUid;
  final String emptyHint;

  /// 스레드 상태 변경(pending→answered 등) 수신 시 부모에 알림(상태칩 갱신용).
  final VoidCallback? onThreadUpdate;

  /// 스레드 첨부(이미지만 표시). [resolver] 가 있어야 실제로 렌더한다.
  final List<QuestionAttachment> attachments;

  /// 서명 URL 리졸버(주입). null 이면 첨부 미표시(기존 동작 유지·하위호환).
  final AttachmentUrlResolver? resolver;

  /// 이미지 첨부 탭 시(전체화면 뷰어 진입 등).
  final void Function(QuestionAttachment)? onOpenImage;

  /// 파일(비이미지) 첨부 탭 시(서명 URL 열기 등). null 이면 칩 탭 무동작.
  final void Function(QuestionAttachment)? onOpenFile;

  /// 첨부 행 insert 실시간 수신 시(부모가 첨부 재조회). publication 에
  /// question_attachments 가 포함돼 있을 때만 도착한다(웹 117 마이그레이션).
  final VoidCallback? onAttachmentInsert;

  /// N21: 이전 페이지가 더 있을 수 있으면 목록 상단에 '이전 대화 불러오기'
  /// 를 노출한다. [onLoadEarlier] 가 null 이면 미노출(하위호환).
  final bool hasEarlier;

  /// '이전 대화 불러오기' 탭 — 부모가 이전 페이지를 controller 에 합친다.
  final Future<void> Function()? onLoadEarlier;

  @override
  State<LiveMessageList> createState() => _LiveMessageListState();
}

class _LiveMessageListState extends State<LiveMessageList> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.realtime.start(
      // 서버 정본 행 — 같은 id 의 낙관적 행이 있으면 교체한다(서버 created_at 유지).
      onMessageInsert: (QuestionMessage m) =>
          widget.controller.upsertFromServer(m),
      onThreadUpdate: widget.onThreadUpdate,
      onAttachmentInsert: widget.onAttachmentInsert,
    );
    _jumpToEndSoon();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    // 구독 정리(누수 금지). 포트는 이 위젯이 소유.
    widget.realtime.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// N21: 이전 페이지 로드 직후엔 맨 아래로 점프하지 않는다(읽던 위치 유지).
  bool _suppressNextJump = false;
  bool _loadingEarlier = false;

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_suppressNextJump) {
      _suppressNextJump = false;
      return;
    }
    _jumpToEndSoon();
  }

  Future<void> _loadEarlier() async {
    final Future<void> Function()? load = widget.onLoadEarlier;
    if (load == null || _loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    _suppressNextJump = true;
    try {
      await load();
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  void _jumpToEndSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<_Row> rows = _buildRows();
    if (rows.isEmpty) {
      return Center(
        child: Text(widget.emptyHint, style: AppType.caption),
      );
    }
    // N21: 상단 '이전 대화 불러오기'(이전 페이지가 있을 수 있을 때만).
    final bool showEarlier = widget.hasEarlier && widget.onLoadEarlier != null;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH, vertical: AppSpacing.s16),
      itemCount: rows.length + (showEarlier ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (showEarlier && i == 0) {
          return Center(
            child: TextButton(
              onPressed: _loadingEarlier ? null : _loadEarlier,
              child: Text(_loadingEarlier ? '불러오는 중…' : '이전 대화 불러오기'),
            ),
          );
        }
        return rows[i - (showEarlier ? 1 : 0)].child;
      },
    );
  }

  /// 메시지 + 첨부(이미지·파일)를 시간순으로 병합한다(첨부 v2 계약 §2-4·§2-6).
  /// - 메시지에 연결된(message_id 일치) 첨부는 그 말풍선 안에(이미지=썸네일, 그 외=파일 칩).
  /// - 연결이 없는 standalone 첨부는 독립 행 — author_id 기준 좌/우 정렬,
  ///   미기록(null, 레거시)은 중앙 중립 카드.
  List<_Row> _buildRows() {
    final List<QuestionMessage> messages = widget.controller.items;
    final AttachmentUrlResolver? resolver = widget.resolver;

    final List<QuestionAttachment> atts = resolver == null
        ? const <QuestionAttachment>[]
        : widget.attachments;
    final Set<String> msgIds =
        messages.map((QuestionMessage m) => m.id).toSet();
    final Map<String, List<QuestionAttachment>> linked =
        <String, List<QuestionAttachment>>{};
    final List<QuestionAttachment> standalone = <QuestionAttachment>[];
    for (final QuestionAttachment a in atts) {
      final String? mid = a.messageId;
      if (mid != null && msgIds.contains(mid)) {
        linked.putIfAbsent(mid, () => <QuestionAttachment>[]).add(a);
      } else {
        standalone.add(a);
      }
    }

    final List<_Row> rows = <_Row>[];
    for (final QuestionMessage m in messages) {
      final bool mine =
          widget.currentUid != null && m.authorId == widget.currentUid;
      final List<Widget> chips = <Widget>[
        for (final QuestionAttachment a in linked[m.id] ?? const <QuestionAttachment>[])
          _attachmentWidget(a, resolver!),
      ];
      rows.add(_Row(
        m.createdAt,
        MessageBubble(message: m, mine: mine, attachments: chips),
      ));
    }
    for (final QuestionAttachment a in standalone) {
      rows.add(_Row(a.createdAt, _standaloneAttachment(a, resolver!)));
    }
    rows.sort((_Row x, _Row y) => x.time.compareTo(y.time));
    return rows;
  }

  /// 첨부 1건 위젯(계약 §2-6): image/* → 썸네일+뷰어, 그 외 → 파일 칩(탭=열기).
  Widget _attachmentWidget(QuestionAttachment a, AttachmentUrlResolver resolver,
      {double imageSize = 180}) {
    if (isImageAttachment(a.mimeType)) {
      return MessageImageAttachment(
        attachment: a,
        resolver: resolver,
        onOpen: () => widget.onOpenImage?.call(a),
        size: imageSize,
      );
    }
    return MessageFileAttachment(
      attachment: a,
      onOpen: () => widget.onOpenFile?.call(a),
    );
  }

  /// standalone 첨부 행(계약 §2-4·§2-5): author_id == 내 uid → 우측, 상대 → 좌측,
  /// 미기록(null, 레거시) → 중앙 중립 카드.
  Widget _standaloneAttachment(
      QuestionAttachment a, AttachmentUrlResolver resolver) {
    final String? author = a.authorId;
    final Alignment alignment = author == null
        ? Alignment.center
        : (widget.currentUid != null && author == widget.currentUid)
            ? Alignment.centerRight
            : Alignment.centerLeft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: alignment,
        child: _attachmentWidget(a, resolver, imageSize: 220),
      ),
    );
  }
}

/// 시간순 병합용 행(메시지 말풍선 or 독립 이미지).
class _Row {
  const _Row(this.time, this.child);
  final DateTime time;
  final Widget child;
}
