import 'dart:async';
import 'dart:io';

import 'package:background_task/background_task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../collections/geoloc.dart';
import '../controllers/app_params/app_params_notifier.dart';
import '../controllers/calendars/calendars_notifier.dart';
import '../controllers/calendars/calendars_response_state.dart';
import '../controllers/geoloc/geoloc.dart';
import '../controllers/holidays/holidays_notifier.dart';
import '../controllers/holidays/holidays_response_state.dart';
import '../controllers/temple/temple.dart';
import '../controllers/walk_record/walk_record.dart';
import '../extensions/extensions.dart';
import '../models/geoloc_model.dart';
import '../models/temple_latlng_model.dart';
import '../models/walk_record_model.dart';
import '../ripository/geolocs_repository.dart';
import '../ripository/isar_repository.dart';
import '../utilities/utilities.dart';
import 'components/daily_geoloc_display_alert.dart';
import 'components/geoloc_map_alert.dart';
import 'components/history_geoloc_list_alert.dart';
import 'parts/geoloc_dialog.dart';
import 'parts/menu_head_icon.dart';

@pragma('vm:entry-point')
void backgroundHandler(Location data) {
  // ignore: always_specify_types
  Future(() async {
    GeolocRepository().getRecentOneGeoloc().then((Geoloc? value) async {
      /////////////////////
      final DateTime now = DateTime.now();
      final DateFormat timeFormat = DateFormat('HH:mm:ss');
      final String currentTime = timeFormat.format(now);

      final Geoloc geoloc = Geoloc()
        ..date = DateTime.now().yyyymmdd
        ..time = currentTime
        ..latitude = data.lat.toString()
        ..longitude = data.lng.toString();
      /////////////////////

      bool isInsert = false;

      int secondDiff = 0;

      if (value != null) {
        secondDiff = DateTime.now()
            .difference(
              DateTime(
                value.date.split('-')[0].toInt(),
                value.date.split('-')[1].toInt(),
                value.date.split('-')[2].toInt(),
                value.time.split(':')[0].toInt(),
                value.time.split(':')[1].toInt(),
                value.time.split(':')[2].toInt(),
              ),
            )
            .inSeconds;
      } else {
        /// 初回
        isInsert = true;
      }

//      debugPrint(secondDiff.toString());

      if (secondDiff >= 60) {
        isInsert = true;
      }

      if (isInsert) {
        // debugPrint('---------');
        // debugPrint(DateTime.now().toString());
        // debugPrint(data.lat.toString());
        // debugPrint(data.lng.toString());
        // debugPrint('---------');

        await IsarRepository.configure();
        IsarRepository.isar.writeTxnSync(() => IsarRepository.isar.geolocs.putSync(geoloc));
      }
    });
  });
}

// ignore: must_be_immutable, unreachable_from_main
class HomeScreen extends ConsumerStatefulWidget {
  // ignore: unreachable_from_main
  HomeScreen({super.key, this.baseYm});

  // ignore: unreachable_from_main
  String? baseYm;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String bgText = 'no start';
  String statusText = 'status';
  bool isEnabledEvenIfKilled = true;

  late final StreamSubscription<Location> _bgDisposer;
  late final StreamSubscription<StatusEvent> _statusDisposer;

  DateTime _calendarMonthFirst = DateTime.now();
  final List<String> _youbiList = <String>[
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday'
  ];
  List<String> _calendarDays = <String>[];

  Map<String, String> _holidayMap = <String, String>{};

  final Utility utility = Utility();

  bool baseYmSetFlag = false;

  List<Geoloc>? geolocList = <Geoloc>[];
  Map<String, List<Geoloc>> geolocMap = <String, List<Geoloc>>{};

  ///
  @override
  void initState() {
    super.initState();

    _bgDisposer = BackgroundTask.instance.stream.listen((Location event) {
      final String message = '${DateTime.now()}: ${event.lat}, ${event.lng}';

      // debugPrint(message);

      setState(() => bgText = message);
    });

    // ignore: always_specify_types
    Future(() async {
      final PermissionStatus result = await Permission.notification.request();
      // debugPrint('notification: $result');

      if (Platform.isAndroid) {
        if (result.isGranted) {
          await BackgroundTask.instance.setAndroidNotification(
            title: 'バックグラウンド処理',
            message: 'バックグラウンド処理を実行中',
          );
        }
      }
    });

    _statusDisposer = BackgroundTask.instance.status.listen((StatusEvent event) {
      final String message = 'status: ${event.status.value}, message: ${event.message}';

      setState(() => statusText = message);
    });

    ref
        .read(geolocControllerProvider.notifier)
        .getYearMonthGeoloc(yearmonth: (widget.baseYm != null) ? widget.baseYm! : DateTime.now().yyyymm);

    ref
        .read(walkRecordControllerProvider.notifier)
        .getYearWalkRecord(yearmonth: (widget.baseYm != null) ? widget.baseYm! : DateTime.now().yyyymm);

    ref.read(templeControllerProvider.notifier).getAllTempleModel();
  }

  ///
  @override
  void dispose() {
    _bgDisposer.cancel();
    _statusDisposer.cancel();
    super.dispose();
  }

  ///
  void _init() {
    _makeGeolocList();
  }

  ///
  @override
  Widget build(BuildContext context) {
    // ignore: always_specify_types
    Future(_init);

    if (widget.baseYm != null && !baseYmSetFlag) {
      // ignore: always_specify_types
      Future(() => ref.read(calendarProvider.notifier).setCalendarYearMonth(baseYm: widget.baseYm));

      baseYmSetFlag = true;
    }

    final CalendarsResponseState calendarState = ref.watch(calendarProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: <Widget>[
            Text(calendarState.baseYearMonth),
            const SizedBox(width: 10),
            SizedBox(
              width: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  IconButton(
                      onPressed: () => _goPrevMonth(),
                      icon: Icon(Icons.arrow_back_ios, color: Colors.white.withOpacity(0.8), size: 14)),
                  IconButton(
                    onPressed: () => (DateTime.now().yyyymm == calendarState.baseYearMonth) ? null : _goNextMonth(),
                    icon: Icon(Icons.arrow_forward_ios,
                        size: 14,
                        color: (DateTime.now().yyyymm == calendarState.baseYearMonth)
                            ? Colors.grey.withOpacity(0.6)
                            : Colors.white.withOpacity(0.8)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      endDrawer: _dispDrawer(),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          utility.getBackGround(),
          Column(children: <Widget>[Expanded(child: _getCalendar())]),
          Positioned(
            bottom: 10,
            right: 10,
            child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent.withOpacity(0.2)),
                onPressed: () {
                  final List<GeolocModel> list = <GeolocModel>[];

                  int i = 0;
                  String keepLat = '';
                  String keepLng = '';
                  ref.watch(geolocControllerProvider.select((GeolocControllerState value) => value.geolocList)).toList()
                    ..sort((GeolocModel a, GeolocModel b) => a.latitude.compareTo(b.latitude))
                    ..sort((GeolocModel a, GeolocModel b) => a.longitude.compareTo(b.longitude))
                    ..forEach((GeolocModel element) {
                      String distance = '';

                      if (i == 0) {
                        list.add(element);
                      } else {
                        final String di = utility.calcDistance(
                          originLat: keepLat.toDouble(),
                          originLng: keepLng.toDouble(),
                          destLat: element.latitude.toDouble(),
                          destLng: element.longitude.toDouble(),
                        );

                        final double dis = di.toDouble() * 1000;

                        final List<String> exDis = dis.toString().split('.');

                        distance = exDis[0];

                        final int? dist = int.tryParse(distance);

                        if (dist != null && dist > 1000) {
                          list.add(element);
                        }
                      }

                      keepLat = element.latitude;
                      keepLng = element.longitude;
                      i++;
                    });

                  ref.read(appParamProvider.notifier).setIsMarkerShow(flag: true);

                  ref.read(appParamProvider.notifier).setSelectedTimeGeoloc();

                  ref.read(appParamProvider.notifier).setSelectedHour(hour: '');

                  GeolocDialog(
                    context: context,
                    widget: GeolocMapAlert(
                      geolocStateList: list,
                      displayMonthMap: true,
                      walkRecord: WalkRecordModel(
                        id: 0,
                        year: '',
                        month: '',
                        day: '',
                        step: 0,
                        distance: 0,
                      ),
                    ),
                  );
                },
                child: const Text('month')),
          ),
        ],
      ),
    );
  }

  ///
  Widget _dispDrawer() {
    return Drawer(
      backgroundColor: Colors.blueGrey.withOpacity(0.2),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.only(left: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 60),
              GestureDetector(
                onTap: () async {
                  final PermissionStatus status = await Permission.location.request();
                  final PermissionStatus statusAlways = await Permission.locationAlways.request();

                  if (status.isGranted && statusAlways.isGranted) {
                    await BackgroundTask.instance.start(isEnabledEvenIfKilled: isEnabledEvenIfKilled);
                    setState(() => bgText = 'start');
                  }
                },
                child: Row(
                  children: <Widget>[
                    const MenuHeadIcon(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
                        margin: const EdgeInsets.all(5),
                        child: const Text('Start'),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final bool isRunning = await BackgroundTask.instance.isRunning;

                  if (context.mounted) {
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('isRunning: $isRunning'),
                        action: SnackBarAction(
                          label: 'close',
                          onPressed: () => ScaffoldMessenger.of(context).clearSnackBars(),
                        ),
                      ),
                    );
                  }
                },
                child: Row(
                  children: <Widget>[
                    const MenuHeadIcon(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
                        margin: const EdgeInsets.all(5),
                        child: const Text('Status'),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: Colors.white.withOpacity(0.4), thickness: 5),
              GestureDetector(
                onTap: () => Navigator.pushReplacement(
                  context,
                  // ignore: inference_failure_on_instance_creation, always_specify_types
                  MaterialPageRoute(
                    builder: (BuildContext context) =>
                        HomeScreen(baseYm: (widget.baseYm != null) ? widget.baseYm : DateTime.now().yyyymm),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const MenuHeadIcon(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
                        margin: const EdgeInsets.all(5),
                        child: const Text('Reload'),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    // ignore: inference_failure_on_instance_creation, always_specify_types
                    MaterialPageRoute(builder: (BuildContext context) => HomeScreen(baseYm: DateTime.now().yyyymm)),
                  );
                },
                child: Row(
                  children: <Widget>[
                    const MenuHeadIcon(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
                        margin: const EdgeInsets.all(5),
                        child: const Text('Today'),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => GeolocDialog(context: context, widget: const HistoryGeolocListAlert()),
                child: Row(
                  children: <Widget>[
                    const MenuHeadIcon(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
                        margin: const EdgeInsets.all(5),
                        child: const Text('History'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ///
  Widget _getCalendar() {
    final Map<String, List<GeolocModel>> geolocStateMap =
        ref.watch(geolocControllerProvider.select((GeolocControllerState value) => value.geolocMap));

    final Map<String, WalkRecordModel> walkRecordMap =
        ref.watch(walkRecordControllerProvider.select((WalkRecordControllerState value) => value.walkRecordMap));

    final Map<String, List<TempleInfoModel>> templeInfoMap =
        ref.watch(templeControllerProvider.select((TempleControllerState value) => value.templeInfoMap));

    final HolidaysResponseState holidayState = ref.watch(holidayProvider);

    if (holidayState.holidayMap.value != null) {
      _holidayMap = holidayState.holidayMap.value!;
    }

    final CalendarsResponseState calendarState = ref.watch(calendarProvider);

    _calendarMonthFirst = DateTime.parse('${calendarState.baseYearMonth}-01 00:00:00');

    final DateTime monthEnd = DateTime.parse('${calendarState.nextYearMonth}-00 00:00:00');

    final int diff = monthEnd.difference(_calendarMonthFirst).inDays;
    final int monthDaysNum = diff + 1;

    final String youbi = _calendarMonthFirst.youbiStr;
    final int youbiNum = _youbiList.indexWhere((String element) => element == youbi);

    final int weekNum = ((monthDaysNum + youbiNum) <= 35) ? 5 : 6;

    // ignore: always_specify_types
    _calendarDays = List.generate(weekNum * 7, (int index) => '');

    for (int i = 0; i < (weekNum * 7); i++) {
      if (i >= youbiNum) {
        final DateTime gendate = _calendarMonthFirst.add(Duration(days: i - youbiNum));

        if (_calendarMonthFirst.month == gendate.month) {
          _calendarDays[i] = gendate.day.toString();
        }
      }
    }

    final List<Widget> list = <Widget>[];
    for (int i = 0; i < weekNum; i++) {
      list.add(_getCalendarRow(
          week: i, geolocStateMap: geolocStateMap, walkRecordMap: walkRecordMap, templeInfoMap: templeInfoMap));
    }

    return SingleChildScrollView(
        child: DefaultTextStyle(style: const TextStyle(fontSize: 10), child: Column(children: list)));
  }

  ///
  Widget _getCalendarRow(
      {required int week,
      required Map<String, List<GeolocModel>> geolocStateMap,
      required Map<String, WalkRecordModel> walkRecordMap,
      required Map<String, List<TempleInfoModel>> templeInfoMap}) {
    final List<Widget> list = <Widget>[];

    for (int i = week * 7; i < ((week + 1) * 7); i++) {
      final String generateYmd = (_calendarDays[i] == '')
          ? ''
          : DateTime(_calendarMonthFirst.year, _calendarMonthFirst.month, _calendarDays[i].toInt()).yyyymmdd;

      final String youbiStr = (_calendarDays[i] == '')
          ? ''
          : DateTime(_calendarMonthFirst.year, _calendarMonthFirst.month, _calendarDays[i].toInt()).youbiStr;

      list.add(
        Expanded(
          child: Stack(
            children: <Widget>[
              if (templeInfoMap[generateYmd] != null) ...<Widget>[
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Icon(FontAwesomeIcons.toriiGate, size: 15, color: Colors.white.withOpacity(0.5)),
                ),
              ],
              Container(
                margin: const EdgeInsets.all(1),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: (_calendarDays[i] == '')
                        ? Colors.transparent
                        : (generateYmd == DateTime.now().yyyymmdd)
                            ? Colors.orangeAccent.withOpacity(0.4)
                            : Colors.white.withOpacity(0.1),
                    width: 3,
                  ),
                  color: (_calendarDays[i] == '')
                      ? Colors.transparent
                      : (DateTime.parse('$generateYmd 00:00:00').isAfter(DateTime.now()))
                          ? Colors.white.withOpacity(0.1)
                          : utility.getYoubiColor(date: generateYmd, youbiStr: youbiStr, holidayMap: _holidayMap),
                ),
                child: (_calendarDays[i] == '')
                    ? const Text('')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(_calendarDays[i].padLeft(2, '0')),
                              Icon(
                                Icons.directions_walk,
                                size: 12,
                                color: (walkRecordMap[generateYmd] != null)
                                    ? Colors.yellowAccent.withOpacity(0.4)
                                    : Colors.grey.withOpacity(0.4),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          ConstrainedBox(
                            constraints: BoxConstraints(minHeight: context.screenSize.height / 9),
                            child: (DateTime.parse('$generateYmd 00:00:00').isAfter(DateTime.now()))
                                ? null
                                : Column(
                                    children: <Widget>[
                                      /////

                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          backgroundColor: (geolocMap[generateYmd] == null)
                                              ? null
                                              : Colors.blueAccent.withOpacity(0.1),
                                        ),
                                        onPressed: (geolocMap[generateYmd] == null)
                                            ? null
                                            : () {
                                                GeolocDialog(
                                                  context: context,
                                                  widget: DailyGeolocDisplayAlert(
                                                    date: DateTime.parse('$generateYmd 00:00:00'),
                                                    geolocStateList: geolocStateMap[generateYmd] ?? <GeolocModel>[],
                                                    walkRecord: walkRecordMap[generateYmd] ??
                                                        WalkRecordModel(
                                                          id: 0,
                                                          year: '',
                                                          month: '',
                                                          day: '',
                                                          step: 0,
                                                          distance: 0,
                                                        ),
                                                    templeInfoMap: templeInfoMap[generateYmd],
                                                  ),
                                                );
                                              },
                                        child: Text(
                                          (geolocMap[generateYmd] != null)
                                              ? geolocMap[generateYmd]!.length.toString()
                                              : '',
                                          style: const TextStyle(fontSize: 8, color: Colors.white),
                                        ),
                                      ),

                                      /////

                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          backgroundColor: (geolocStateMap[generateYmd] == null)
                                              ? null
                                              : Colors.greenAccent.withOpacity(0.1),
                                        ),
                                        onPressed: (geolocStateMap[generateYmd] == null)
                                            ? null
                                            : () {
                                                ref.read(appParamProvider.notifier).setIsMarkerShow(flag: false);

                                                GeolocDialog(
                                                  context: context,
                                                  widget: GeolocMapAlert(
                                                    geolocStateList: geolocStateMap[generateYmd] ?? <GeolocModel>[],
                                                    displayMonthMap: false,
                                                    walkRecord: walkRecordMap[generateYmd] ??
                                                        WalkRecordModel(
                                                          id: 0,
                                                          year: '',
                                                          month: '',
                                                          day: '',
                                                          step: 0,
                                                          distance: 0,
                                                        ),
                                                    templeInfoList: templeInfoMap[generateYmd],
                                                  ),
                                                );
                                              },
                                        child: Text(
                                          (geolocStateMap[generateYmd] != null)
                                              ? geolocStateMap[generateYmd]!.length.toString()
                                              : '',
                                          style: const TextStyle(fontSize: 8, color: Colors.white),
                                        ),
                                      ),

                                      /////
                                    ],
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: list);
  }

  ///
  void _goPrevMonth() {
    final CalendarsResponseState calendarState = ref.watch(calendarProvider);

    Navigator.pushReplacement(
      context,
      // ignore: inference_failure_on_instance_creation, always_specify_types
      MaterialPageRoute(builder: (BuildContext context) => HomeScreen(baseYm: calendarState.prevYearMonth)),
    );
  }

  ///
  void _goNextMonth() {
    final CalendarsResponseState calendarState = ref.watch(calendarProvider);

    Navigator.pushReplacement(
      context,
      // ignore: inference_failure_on_instance_creation, always_specify_types
      MaterialPageRoute(builder: (BuildContext context) => HomeScreen(baseYm: calendarState.nextYearMonth)),
    );
  }

  ///
  Future<void> _makeGeolocList() async {
    GeolocRepository().getAllGeoloc().then((List<Geoloc>? value) {
      if (mounted) {
        setState(() {
          geolocList = value;

          if (value!.isNotEmpty) {
            for (final Geoloc element in value) {
              geolocMap[element.date] = <Geoloc>[];
            }

            for (final Geoloc element in value) {
              geolocMap[element.date]?.add(element);
            }
          }
        });
      }
    });
  }
}
