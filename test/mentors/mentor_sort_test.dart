import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/mentors/data/mentor_sort.dart';

MentorListItem _m(
  String id, {
  DateTime? created,
  double? rating,
  int reviews = 0,
}) =>
    MentorListItem(
      id: id,
      nickname: id,
      createdAt: created,
      avgRating: rating,
      reviewCount: reviews,
    );

List<String> _ids(List<MentorListItem> l) =>
    l.map((MentorListItem e) => e.id).toList();

void main() {
  final MentorListItem a =
      _m('a', created: DateTime(2026, 1, 1), rating: 4.0, reviews: 10);
  final MentorListItem b =
      _m('b', created: DateTime(2026, 3, 1), rating: 5.0, reviews: 2);
  final MentorListItem c = _m('c', created: DateTime(2026, 2, 1)); // 값 없음(평점 X)
  final List<MentorListItem> src = <MentorListItem>[a, b, c];

  test('최신순: createdAt 내림차순', () {
    expect(_ids(sortMentors(src, MentorSort.latest)), <String>['b', 'c', 'a']);
  });

  test('별점높은순: avgRating 내림차순, 리뷰 없음은 뒤', () {
    expect(
        _ids(sortMentors(src, MentorSort.ratingHigh)), <String>['b', 'a', 'c']);
  });

  test('리뷰많은순: reviewCount 내림차순', () {
    expect(
        _ids(sortMentors(src, MentorSort.reviewMany)), <String>['a', 'b', 'c']);
  });

  test('입력 리스트는 불변(새 리스트 반환)', () {
    sortMentors(src, MentorSort.reviewMany);
    expect(_ids(src), <String>['a', 'b', 'c']);
  });

  test('정렬 옵션 3종 — 가격낮은순 제거(Commerce-Zero: 가격 미노출)', () {
    // 가격순이 enum·라벨·메뉴 어디에도 남아있지 않음.
    expect(MentorSort.values.length, 3);
    expect(MentorSort.values, <MentorSort>[
      MentorSort.latest,
      MentorSort.ratingHigh,
      MentorSort.reviewMany,
    ]);
    final List<String> labels = MentorSort.values.map(mentorSortLabel).toList();
    expect(labels, <String>['최신순', '별점높은순', '리뷰많은순']);
    expect(labels.contains('가격낮은순'), isFalse);
  });
}
