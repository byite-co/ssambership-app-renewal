import 'mentor_models.dart';

/// 멘토 목록 정렬 옵션 — 데이터로 뒷받침되는 것만.
/// 최신은 기존 데이터, 별점·리뷰는 공개(visible) 리뷰 집계(MentorListItem에 실림).
/// ★ 가격은 앱에서 노출하지 않으므로(Commerce-Zero) '가격낮은순'은 제공하지 않는다.
enum MentorSort { latest, ratingHigh, reviewMany }

String mentorSortLabel(MentorSort s) {
  switch (s) {
    case MentorSort.latest:
      return '최신순';
    case MentorSort.ratingHigh:
      return '별점높은순';
    case MentorSort.reviewMany:
      return '리뷰많은순';
  }
}

/// 정렬된 새 리스트를 돌려준다(입력 불변). 값 없음(평점 미상)은 항상 뒤로.
List<MentorListItem> sortMentors(List<MentorListItem> src, MentorSort sort) {
  final List<MentorListItem> list = <MentorListItem>[...src];
  switch (sort) {
    case MentorSort.latest:
      list.sort((MentorListItem a, MentorListItem b) {
        final DateTime ad =
            a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime bd =
            b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
    case MentorSort.ratingHigh:
      list.sort((MentorListItem a, MentorListItem b) {
        final double ar = a.avgRating ?? -1;
        final double br = b.avgRating ?? -1;
        final int c = br.compareTo(ar);
        return c != 0 ? c : b.reviewCount.compareTo(a.reviewCount);
      });
    case MentorSort.reviewMany:
      list.sort((MentorListItem a, MentorListItem b) {
        final int c = b.reviewCount.compareTo(a.reviewCount);
        return c != 0 ? c : (b.avgRating ?? -1).compareTo(a.avgRating ?? -1);
      });
  }
  return list;
}
