import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/core/scan/scan_source_picker.dart';

/// 소스 무관 고정 결과를 돌려주는 스캔 포트 fake(플러그인 비접촉).
class FakeScanPort implements ScanSourcePort {
  FakeScanPort({this.result, this.error});

  PickedImage? result;
  Object? error;
  final List<ScanSource> calls = <ScanSource>[];

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pick(ScanSource source) async {
    calls.add(source);
    final Object? e = error;
    if (e != null) throw e;
    return result;
  }
}
