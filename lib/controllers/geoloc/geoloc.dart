import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/http/client.dart';
import '../../extensions/extensions.dart';
import '../../models/geoloc_model.dart';
import '../../utilities/utilities.dart';

part 'geoloc.freezed.dart';

part 'geoloc.g.dart';

@freezed
class GeolocControllerState with _$GeolocControllerState {
  const factory GeolocControllerState({
    @Default(<GeolocModel>[]) List<GeolocModel> geolocList,
    @Default(<String, List<GeolocModel>>{}) Map<String, List<GeolocModel>> geolocMap,
  }) = _GeolocControllerState;
}

@Riverpod(keepAlive: true)
class GeolocController extends _$GeolocController {
  final Utility utility = Utility();

  ///
  @override
  GeolocControllerState build() => const GeolocControllerState();

  ///
  Future<void> getYearMonthGeoloc({required String yearmonth}) async {
    final HttpClient client = ref.read(httpClientProvider);

    // ignore: always_specify_types
    await client.get(path: 'geoloc/yearmonth/$yearmonth').then((value) {
      final List<GeolocModel> list = <GeolocModel>[];
      final Map<String, List<GeolocModel>> map = <String, List<GeolocModel>>{};

      // ignore: avoid_dynamic_calls
      for (int i = 0; i < value.length.toString().toInt(); i++) {
        // ignore: avoid_dynamic_calls
        final GeolocModel val = GeolocModel.fromJson(value[i] as Map<String, dynamic>);

        list.add(val);

        map['${val.year}-${val.month}-${val.day}'] = <GeolocModel>[];
      }

      // ignore: avoid_dynamic_calls
      for (int i = 0; i < value.length.toString().toInt(); i++) {
        // ignore: avoid_dynamic_calls
        final GeolocModel val = GeolocModel.fromJson(value[i] as Map<String, dynamic>);

        map['${val.year}-${val.month}-${val.day}']?.add(val);
      }

      state = state.copyWith(geolocList: list, geolocMap: map);
      // ignore: always_specify_types
    }).catchError((error, _) {
      utility.showError('予期せぬエラーが発生しました');
    });
  }

  ///
  Future<void> inputGeoloc({required Map<String, dynamic> map}) async {
    // ignore: always_specify_types
    await ref.read(httpClientProvider).post(path: 'geoloc', body: map).then((value) {}).catchError((error, _) {
      utility.showError('予期せぬエラーが発生しました');
    });
  }

  ///
  Future<void> deleteGeoloc({required String date}) async {
    // ignore: always_specify_types
    await ref
        .read(httpClientProvider)
        .deleteReturnBodyString(path: 'geoloc/date/$date')
        // ignore: always_specify_types
        .then((value) {})
        // ignore: always_specify_types
        .catchError((error, _) {
      utility.showError('予期せぬエラーが発生しました');
    });
  }
}
