import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpHeaders, HttpClient;

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as af_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, SystemChrome, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as r;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:koruelement/pushKORU.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:provider/provider.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

import 'main.dart';

// Убрали import 'loade.dart'; — лоадер заменён на локальный JamKoruLoader

// ============================================================================
// Константы
// ============================================================================
const String kChestKeyLoadedOnce = "loaded_event_sent_once";
const String kShipStatEndpoint = "https://api.koruelement.fun/stat";
const String kChestKeyCachedParrot = "cached_fcm_token";

// ============================================================================
// JamKoruLoader — новый лоадер с текстом KORU и зелёным свечением в стиле джунглей
// ============================================================================
class JamKoruLoader extends StatefulWidget {
  const JamKoruLoader({Key? key}) : super(key: key);

  @override
  State<JamKoruLoader> createState() => _JamKoruLoaderState();
}

class _JamKoruLoaderState extends State<JamKoruLoader> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  late Animation<double> _blur;
  late Animation<Color?> _glowColor;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.08).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _blur = Tween<double>(begin: 10.0, end: 26.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _glowColor = ColorTween(
      begin: const Color(0xFF00FF66), // сочный неон-зелёный
      end: const Color(0xFF9BFF00),   // лаймово-джунглевый
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Полный чёрный фон, центрированный текст KORU с многоуровневой тенью
    return Container(
      color: Colors.black,
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final c = _glowColor.value ?? const Color(0xFF00FF66);
            return Transform.scale(
              scale: _pulse.value,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Мягкое «ореольное» свечение, как лианы/туман джунглей
                  Container(
                    width: 280,
                    height: 120,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(color: c.withOpacity(0.28), blurRadius: _blur.value, spreadRadius: 16),
                        BoxShadow(color: c.withOpacity(0.18), blurRadius: _blur.value * 1.4, spreadRadius: 24),
                        BoxShadow(color: c.withOpacity(0.10), blurRadius: _blur.value * 2.2, spreadRadius: 42),
                      ],
                    ),
                  ),
                  // Слово KORU
                  Text(
                    'KORU',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c,
                      fontFamily: 'Roboto',
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                      shadows: [
                        Shadow(color: c.withOpacity(0.9), blurRadius: 18, offset: const Offset(0, 0)),
                        Shadow(color: c.withOpacity(0.6), blurRadius: 36, offset: const Offset(0, 0)),
                        Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 2, offset: const Offset(0, 1)),
                      ],
                    ),
                  ),
                  // Тонкий зелёный блик поверх, создающий «влажный» эффект
                  IgnorePointer(
                    child: Container(
                      width: 320,
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.4),
                          radius: 1.0,
                          colors: [
                            c.withOpacity(0.16),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// JamBarrel (сервисы/синглтоны)
// ============================================================================
class JamBarrel {
  static final JamBarrel _yaBarrel = JamBarrel._irie();
  JamBarrel._irie();

  factory JamBarrel() => _yaBarrel;

  final FlutterSecureStorage yaChest = const FlutterSecureStorage();
  final JamLog yaLog = JamLog();
  final Connectivity yaNetLookout = Connectivity();
}

class JamLog {
  final Logger _jamaLogger = Logger();
  void i(Object msg) => _jamaLogger.i(msg);
  void w(Object msg) => _jamaLogger.w(msg);
  void e(Object msg) => _jamaLogger.e(msg);
}

// ============================================================================
// JamWire (сеть/данные)
// ============================================================================
class JamWire {
  final JamBarrel _barrel = JamBarrel();

  Future<bool> yaNetIsUp() async {
    final conn = await _barrel.yaNetLookout.checkConnectivity();
    return conn != ConnectivityResult.none;
  }

  Future<void> yaPostJson(String url, Map<String, dynamic> cargo) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(cargo),
      );
    } catch (e) {
      _barrel.yaLog.e("castBottleJson error: $e");
    }
  }
}

// ============================================================================
// JamQuarter (инфа об устройстве)
// ============================================================================
class JamQuarter {
  String? yaShipId;
  String? yaVoyageId = "mafia-one-off";
  String? yaDeckPlatform;
  String? yaDeckBuild;
  String? yaAppVer;
  String? yaLang;
  String? yaTz;
  bool yaPushEnabled = true;

  Future<void> yaGather() async {
    final dev = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await dev.androidInfo;
      yaShipId = a.id;
      yaDeckPlatform = "android";
      yaDeckBuild = a.version.release;
    } else if (Platform.isIOS) {
      final i = await dev.iosInfo;
      yaShipId = i.identifierForVendor;
      yaDeckPlatform = "ios";
      yaDeckBuild = i.systemVersion;
    }
    final info = await PackageInfo.fromPlatform();
    yaAppVer = info.version;
    yaLang = Platform.localeName.split('_')[0];
    yaTz = tz_zone.local.name;
    yaVoyageId = "voyage-${DateTime.now().millisecondsSinceEpoch}";
  }

  Map<String, dynamic> yaToMap({String? parrot}) => {
    "fcm_token": parrot ?? 'missing_token',
    "device_id": yaShipId ?? 'missing_id',
    "app_name": "koruelement",
    "instance_id": yaVoyageId ?? 'missing_session',
    "platform": yaDeckPlatform ?? 'missing_system',
    "os_version": yaDeckBuild ?? 'missing_build',
    "app_version": yaAppVer ?? 'missing_app',
    "language": yaLang ?? 'en',
    "timezone": yaTz ?? 'UTC',
    "push_enabled": yaPushEnabled,
  };
}

// ============================================================================
// JamConsigliere (AppsFlyer)
// ============================================================================
class JamConsigliere with ChangeNotifier {
  af_core.AppsFlyerOptions? _yaOpts;
  af_core.AppsflyerSdk? _yaSdk;

  String yaAfUid = "";
  String yaAfPayload = "";

  void yaStart(VoidCallback nudge) {
    final cfg = af_core.AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6680193295",
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );
    _yaOpts = cfg;
    _yaSdk = af_core.AppsflyerSdk(cfg);

    _yaSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    _yaSdk?.startSDK(
      onSuccess: () => JamBarrel().yaLog.i("Consigliere hoisted"),
      onError: (int c, String m) => JamBarrel().yaLog.e("Consigliere storm $c: $m"),
    );
    _yaSdk?.onInstallConversionData((loot) {
      yaAfPayload = loot.toString();
      nudge();
      notifyListeners();
    });
    _yaSdk?.getAppsFlyerUID().then((v) {
      yaAfUid = v.toString();
      nudge();
      notifyListeners();
    });
  }
}

// ============================================================================
// Riverpod/Provider
// ============================================================================
final jamQuarterProvider = r.FutureProvider<JamQuarter>((ref) async {
  final q = JamQuarter();
  await q.yaGather();
  return q;
});

final jamConsigliereProvider = p.ChangeNotifierProvider<JamConsigliere>(
  create: (_) => JamConsigliere(),
);

// ============================================================================
// Parrot (FCM) — фон
// ============================================================================
@pragma('vm:entry-point')
Future<void> jamParrotBg(RemoteMessage msg) async {
  JamBarrel().yaLog.i("bg-parrot: ${msg.messageId}");
  JamBarrel().yaLog.i("bg-cargo: ${msg.data}");
}

// ============================================================================
// JamParrotBridge (токен из нативного канала)
// ============================================================================
class JamParrotBridge extends ChangeNotifier {
  final JamBarrel _barrel = JamBarrel();
  String? _yaFeather;
  final List<void Function(String)> _yaAwaiters = [];

  String? get yaToken => _yaFeather;

  JamParrotBridge() {
    const MethodChannel('com.example.fcm/token').setMethodCallHandler((call) async {
      if (call.method == 'setToken') {
        final String s = call.arguments as String;
        if (s.isNotEmpty) {
          _yaSetFeather(s);
        }
      }
    });
    _yaRestoreFeather();
  }

  Future<void> _yaRestoreFeather() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = sp.getString(kChestKeyCachedParrot);
      if (cached != null && cached.isNotEmpty) {
        _yaSetFeather(cached, notifyNative: false);
      } else {
        final ss = await _barrel.yaChest.read(key: kChestKeyCachedParrot);
        if (ss != null && ss.isNotEmpty) {
          _yaSetFeather(ss, notifyNative: false);
        }
      }
    } catch (_) {}
  }

  void _yaSetFeather(String t, {bool notifyNative = true}) async {
    _yaFeather = t;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kChestKeyCachedParrot, t);
      await _barrel.yaChest.write(key: kChestKeyCachedParrot, value: t);
    } catch (_) {}
    for (final cb in List.of(_yaAwaiters)) {
      try {
        cb(t);
      } catch (e) {
        _barrel.yaLog.w("parrot-waiter error: $e");
      }
    }
    _yaAwaiters.clear();
    notifyListeners();
  }

  Future<void> yaAwaitFeather(Function(String t) onToken) async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (_yaFeather != null && _yaFeather!.isNotEmpty) {
        onToken(_yaFeather!);
        return;
      }
      _yaAwaiters.add(onToken);
    } catch (e) {
      _barrel.yaLog.e("ParrotBridge awaitFeather: $e");
    }
  }
}

// ============================================================================
// JamSplash (Splash)
// ============================================================================
class JamSplash extends StatefulWidget {
  const JamSplash({Key? key}) : super(key: key);

  @override
  State<JamSplash> createState() => _JamSplashState();
}

class _JamSplashState extends State<JamSplash> {
  final JamParrotBridge _yaParrot = JamParrotBridge();
  bool _yaOnce = false;
  Timer? _yaFallback;
  bool _yaCoverMuted = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    _yaParrot.yaAwaitFeather((sig) => _yaGo(sig));
    _yaFallback = Timer(const Duration(seconds: 8), () => _yaGo(''));

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _yaCoverMuted = true);
    });
  }

  void _yaGo(String sig) {
    if (_yaOnce) return;
    _yaOnce = true;
    _yaFallback?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => JamHarbor(signal: sig)),
    );
  }

  @override
  void dispose() {
    _yaFallback?.cancel();
    _yaParrot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: const JamKoruLoader(),
    );
  }
}

// ============================================================================
// MVVM: JamBosun, JamCourier
// ============================================================================
class JamBosun with ChangeNotifier {
  final JamQuarter yaQuarter;
  final JamConsigliere yaConsig;

  JamBosun({required this.yaQuarter, required this.yaConsig});

  Map<String, dynamic> yaDeviceCargo(String? token) => yaQuarter.yaToMap(parrot: token);

  Map<String, dynamic> yaAFCargo(String? token) => {
    "content": {
      "af_data": yaConsig.yaAfPayload,
      "af_id": yaConsig.yaAfUid,
      "fb_app_name": "koruelement",
      "app_name": "koruelement",
      "deep": null,
      "bundle_identifier": "koruelement.koruelement.koruelement.koruelement",
      "app_version": "1.0.0",
      "apple_id": "6680193295",
      "fcm_token": token ?? "no_token",
      "device_id": yaQuarter.yaShipId ?? "no_device",
      "instance_id": yaQuarter.yaVoyageId ?? "no_instance",
      "platform": yaQuarter.yaDeckPlatform ?? "no_type",
      "os_version": yaQuarter.yaDeckBuild ?? "no_os",
      "app_version": yaQuarter.yaAppVer ?? "no_app",
      "language": yaQuarter.yaLang ?? "en",
      "timezone": yaQuarter.yaTz ?? "UTC",
      "push_enabled": yaQuarter.yaPushEnabled,
      "useruid": yaConsig.yaAfUid,
    },
  };
}

class JamCourier {
  final JamBosun yaModel;
  final InAppWebViewController Function() yaGetWeb;

  JamCourier({required this.yaModel, required this.yaGetWeb});

  Future<void> yaStoreDeviceToLocal(String? token) async {
    final m = yaModel.yaDeviceCargo(token);
    await yaGetWeb().evaluateJavascript(source: '''
localStorage.setItem('app_data', JSON.stringify(${jsonEncode(m)}));
''');
  }

  Future<void> yaSendRaw(String? token) async {
    final payload = yaModel.yaAFCargo(token);
    final jsonString = jsonEncode(payload);
    JamBarrel().yaLog.i("SendRawData: $jsonString");
    await yaGetWeb().evaluateJavascript(source: "sendRawData(${jsonEncode(jsonString)});");
  }
}

// ============================================================================
// Переходы/статистика
// ============================================================================
Future<String> yaFinalUrl(String startUrl, {int maxHops = 10}) async {
  final client = HttpClient();

  try {
    var current = Uri.parse(startUrl);
    for (int i = 0; i < maxHops; i++) {
      final req = await client.getUrl(current);
      req.followRedirects = false;
      final res = await req.close();
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        if (loc == null || loc.isEmpty) break;
        final next = Uri.parse(loc);
        current = next.hasScheme ? next : current.resolveUri(next);
        continue;
      }
      return current.toString();
    }
    return current.toString();
  } catch (e) {
    debugPrint("chartFinalUrl error: $e");
    return startUrl;
  } finally {
    client.close(force: true);
  }
}

Future<void> yaPostStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final finalUrl = await yaFinalUrl(url);
    final payload = {
      "event": event,
      "timestart": timeStart,
      "timefinsh": timeFinish,
      "url": finalUrl,
      "appleID": "6753014534",
      "open_count": "$appSid/$timeStart",
    };

    print("loadingstatinsic $payload");
    final res = await http.post(
      Uri.parse("$kShipStatEndpoint/$appSid"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );
    print(" ur _loaded$kShipStatEndpoint/$appSid");
    debugPrint("_postStat status=${res.statusCode} body=${res.body}");
  } catch (e) {
    debugPrint("_postStat error: $e");
  }
}

// ============================================================================
// JamHarbor (главный WebView)
// ============================================================================
class JamHarbor extends StatefulWidget {
  final String? signal;
  const JamHarbor({super.key, required this.signal});

  @override
  State<JamHarbor> createState() => _JamHarborState();
}

class _JamHarborState extends State<JamHarbor> with WidgetsBindingObserver {
  late InAppWebViewController _yaPier;
  bool _yaBusyWheel = false;
  final String _yaHome = "https://api.koruelement.fun/";
  final JamQuarter _yaQuarter = JamQuarter();
  final JamConsigliere _yaConsig = JamConsigliere();

  int _yaHatchKey = 0;
  DateTime? _yaSleepAt;
  bool _yaVeil = false;
  double _yaWarmRatio = 0.0;
  late Timer _yaWarmTimer;
  final int _yaWarmSecs = 6;
  bool _yaCover = true;

  bool _yaLoadedOnceSent = false;
  int? _yaFirstPageTs;

  JamCourier? _yaCourier;
  JamBosun? _yaBosun;

  String _yaCurrentUrl = "";
  var _yaStartLoadTs = 0;

  final Set<String> _yaSchemes = {
    'tg', 'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
    'fb', 'instagram', 'twitter', 'x',
  };

  final Set<String> _yaExternalHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com', 'www.bnl.com',
    'x.com', 'www.x.com',
    'twitter.com', 'www.twitter.com',
    'facebook.com', 'www.facebook.com', 'm.facebook.com',
    'instagram.com', 'www.instagram.com',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _yaFirstPageTs = DateTime.now().millisecondsSinceEpoch;

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _yaCover = false);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
    });
    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => _yaVeil = true);
    });

    _yaBoot();
  }

  Future<void> _yaLoadOnceFlag() async {
    final sp = await SharedPreferences.getInstance();
    _yaLoadedOnceSent = sp.getBool(kChestKeyLoadedOnce) ?? false;
  }

  Future<void> _yaSaveOnceFlag() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kChestKeyLoadedOnce, true);
    _yaLoadedOnceSent = true;
  }

  Future<void> yaSendLoadedOnce({required String url, required int timestart}) async {
    if (_yaLoadedOnceSent) {
      print("Loaded already sent, skipping");
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await yaPostStat(
      event: "Loaded",
      timeStart: timestart,
      timeFinish: now,
      url: url,
      appSid: _yaConsig.yaAfUid,
      firstPageLoadTs: _yaFirstPageTs,
    );
    await _yaSaveOnceFlag();
  }

  void _yaBoot() {
    _yaWarmUp();
    _yaWireParrot();
    _yaConsig.yaStart(() => setState(() {}));
    _yaBindBell();
    _yaPrepQuarter();

    Future.delayed(const Duration(seconds: 6), () async {
      await _yaPushDevice();
      await _yaPushAF();
    });
  }

  void _yaWireParrot() {
    FirebaseMessaging.onMessage.listen((msg) {
      final link = msg.data['uri'];
      if (link != null) {
        _yaSail(link.toString());
      } else {
        _yaBackHome();
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final link = msg.data['uri'];
      if (link != null) {
        _yaSail(link.toString());
      } else {
        _yaBackHome();
      }
    });
  }

  void _yaBindBell() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(call.arguments);
        if (payload["uri"] != null && !payload["uri"].contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => JamCaptainDeck(payload["uri"].toString())),
                (route) => false,
          );
        }
      }
    });
  }

  Future<void> _yaPrepQuarter() async {
    try {
      await _yaQuarter.yaGather();
      await _yaAskPushPerms();
      _yaBosun = JamBosun(yaQuarter: _yaQuarter, yaConsig: _yaConsig);
      _yaCourier = JamCourier(yaModel: _yaBosun!, yaGetWeb: () => _yaPier);
      await _yaLoadOnceFlag();
    } catch (e) {
      JamBarrel().yaLog.e("prepare-quartermaster fail: $e");
    }
  }

  Future<void> _yaAskPushPerms() async {
    FirebaseMessaging m = FirebaseMessaging.instance;
    await m.requestPermission(alert: true, badge: true, sound: true);
  }

  void _yaSail(String link) async {
    if (_yaPier != null) {
      await _yaPier.loadUrl(urlRequest: URLRequest(url: WebUri(link)));
    }
  }

  void _yaBackHome() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (_yaPier != null) {
        _yaPier.loadUrl(urlRequest: URLRequest(url: WebUri(_yaHome)));
      }
    });
  }

  Future<void> _yaPushDevice() async {
    JamBarrel().yaLog.i("TOKEN ship ${widget.signal}");
    if (!mounted) return;
    setState(() => _yaBusyWheel = true);
    try {
      await _yaCourier?.yaStoreDeviceToLocal(widget.signal);
    } finally {
      if (mounted) setState(() => _yaBusyWheel = false);
    }
  }

  Future<void> _yaPushAF() async {
    await _yaCourier?.yaSendRaw(widget.signal);
  }

  void _yaWarmUp() {
    int n = 0;
    _yaWarmRatio = 0.0;
    _yaWarmTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      setState(() {
        n++;
        _yaWarmRatio = n / (_yaWarmSecs * 10);
        if (_yaWarmRatio >= 1.0) {
          _yaWarmRatio = 1.0;
          _yaWarmTimer.cancel();
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState tide) {
    if (tide == AppLifecycleState.paused) {
      _yaSleepAt = DateTime.now();
    }
    if (tide == AppLifecycleState.resumed) {
      if (Platform.isIOS && _yaSleepAt != null) {
        final now = DateTime.now();
        final drift = now.difference(_yaSleepAt!);
        if (drift > const Duration(minutes: 25)) {
          _yaReboard();
        }
      }
      _yaSleepAt = null;
    }
  }

  void _yaReboard() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => JamHarbor(signal: widget.signal)),
            (route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _yaWarmTimer.cancel();
    super.dispose();
  }

  // ================== URL helpers ==================
  bool _yaIsBareMail(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  Uri _yaToMailto(Uri u) {
    final full = u.toString();
    final parts = full.split('?');
    final email = parts.first;
    final qp = parts.length > 1 ? Uri.splitQueryString(parts[1]) : <String, String>{};
    return Uri(scheme: 'mailto', path: email, queryParameters: qp.isEmpty ? null : qp);
  }

  bool _yaIsPlatformish(Uri u) {
    final s = u.scheme.toLowerCase();
    if (_yaSchemes.contains(s)) return true;

    if (s == 'http' || s == 'https') {
      final h = u.host.toLowerCase();
      if (_yaExternalHosts.contains(h)) return true;
      if (h.endsWith('t.me')) return true;
      if (h.endsWith('wa.me')) return true;
      if (h.endsWith('m.me')) return true;
      if (h.endsWith('signal.me')) return true;
      if (h.endsWith('x.com')) return true;
      if (h.endsWith('twitter.com')) return true;
      if (h.endsWith('facebook.com')) return true;
      if (h.endsWith('instagram.com')) return true;
    }
    return false;
  }

  Uri _yaHttpize(Uri u) {
    final s = u.scheme.toLowerCase();

    if (s == 'tg' || s == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {if (qp['start'] != null) 'start': qp['start']!});
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if ((s == 'http' || s == 'https') && u.host.toLowerCase().endsWith('t.me')) {
      return u;
    }

    if (s == 'viber') return u;

    if (s == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${_yaDigits(phone)}', {if (text != null && text.isNotEmpty) 'text': text});
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if ((s == 'http' || s == 'https') &&
        (u.host.toLowerCase().endsWith('wa.me') || u.host.toLowerCase().endsWith('whatsapp.com'))) {
      return u;
    }

    if (s == 'skype') return u;

    if (s == 'fb-messenger') {
      final path = u.pathSegments.isNotEmpty ? u.pathSegments.join('/') : '';
      final qp = u.queryParameters;
      final id = qp['id'] ?? qp['user'] ?? path;
      if (id.isNotEmpty) {
        return Uri.https('m.me', '/$id', u.queryParameters.isEmpty ? null : u.queryParameters);
      }
      return Uri.https('m.me', '/', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if (s == 'sgnl') {
      final qp = u.queryParameters;
      final ph = qp['phone'];
      final un = u.queryParameters['username'];
      if (ph != null && ph.isNotEmpty) return Uri.https('signal.me', '/#p/${_yaDigits(ph)}');
      if (un != null && un.isNotEmpty) return Uri.https('signal.me', '/#u/$un');
      final path = u.pathSegments.join('/');
      if (path.isNotEmpty) return Uri.https('signal.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
      return u;
    }

    if (s == 'tel') {
      return Uri.parse('tel:${_yaDigits(u.path)}');
    }

    if (s == 'mailto') return u;

    if (s == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if ((s == 'http' || s == 'https')) {
      final host = u.host.toLowerCase();
      if (host.endsWith('x.com') ||
          host.endsWith('twitter.com') ||
          host.endsWith('facebook.com') ||
          host.startsWith('m.facebook.com') ||
          host.endsWith('instagram.com')) {
        return u;
      }
    }

    if (s == 'fb' || s == 'instagram' || s == 'twitter' || s == 'x') {
      return u;
    }

    return u;
  }

  Future<bool> _yaOpenMailWeb(Uri mailto) async {
    final u = _yaGmailize(mailto);
    return await _yaOpenWeb(u);
  }

  Uri _yaGmailize(Uri m) {
    final qp = m.queryParameters;
    final params = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (m.path.isNotEmpty) 'to': m.path,
      if ((qp['subject'] ?? '').isNotEmpty) 'su': qp['subject']!,
      if ((qp['body'] ?? '').isNotEmpty) 'body': qp['body']!,
      if ((qp['cc'] ?? '').isNotEmpty) 'cc': qp['cc']!,
      if ((qp['bcc'] ?? '').isNotEmpty) 'bcc': qp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', params);
  }

  Future<bool> _yaOpenWeb(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openInAppBrowser error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String _yaDigits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  @override
  Widget build(BuildContext context) {
    _yaBindBell(); // повторная привязка

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_yaCover)
              const JamKoruLoader()
            else
              Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    InAppWebView(
                      key: ValueKey(_yaHatchKey),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        disableDefaultErrorPage: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        allowsPictureInPictureMediaPlayback: true,
                        useOnDownloadStart: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        transparentBackground: true,
                      ),
                      initialUrlRequest: URLRequest(url: WebUri(_yaHome)),
                      onWebViewCreated: (c) {
                        _yaPier = c;

                        _yaBosun ??= JamBosun(yaQuarter: _yaQuarter, yaConsig: _yaConsig);
                        _yaCourier ??= JamCourier(yaModel: _yaBosun!, yaGetWeb: () => _yaPier);

                        _yaPier.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (args) {
                            try {
                              final saved = args.isNotEmpty &&
                                  args[0] is Map &&
                                  args[0]['savedata'].toString() == "false";

                              print("Load True " + args[0].toString());
                              if (saved) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (context) => WebViewWithLoader()),
                                      (route) => false,
                                );
                              }
                            } catch (_) {}
                            if (args.isEmpty) return null;
                            try {
                              return args.reduce((curr, next) => curr + next);
                            } catch (_) {
                              return args.first;
                            }
                          },
                        );
                      },
                      onLoadStart: (c, u) async {
                        setState(() {
                          _yaStartLoadTs = DateTime.now().millisecondsSinceEpoch;
                        });
                        setState(() => _yaBusyWheel = true);
                        final v = u;
                        if (v != null) {
                          if (_yaIsBareMail(v)) {
                            try {
                              await c.stopLoading();
                            } catch (_) {}
                            final mailto = _yaToMailto(v);
                            await _yaOpenMailWeb(mailto);
                            return;
                          }
                          final sch = v.scheme.toLowerCase();
                          if (sch != 'http' && sch != 'https') {
                            try {
                              await c.stopLoading();
                            } catch (_) {}
                          }
                        }
                      },
                      onLoadError: (controller, url, code, message) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "InAppWebViewError(code=$code, message=$message)";
                        await yaPostStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: url?.toString() ?? '',
                          appSid: _yaConsig.yaAfUid,
                          firstPageLoadTs: _yaFirstPageTs,
                        );
                        if (mounted) setState(() => _yaBusyWheel = false);
                      },
                      onReceivedHttpError: (controller, request, errorResponse) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "HTTPError(status=${errorResponse.statusCode}, reason=${errorResponse.reasonPhrase})";
                        await yaPostStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appSid: _yaConsig.yaAfUid,
                          firstPageLoadTs: _yaFirstPageTs,
                        );
                      },
                      onReceivedError: (controller, request, error) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final desc = (error.description ?? '').toString();
                        final ev = "WebResourceError(code=${error}, message=$desc)";
                        await yaPostStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appSid: _yaConsig.yaAfUid,
                          firstPageLoadTs: _yaFirstPageTs,
                        );
                      },
                      onLoadStop: (c, u) async {
                        await c.evaluateJavascript(source: "console.log('Harbor up!');");
                        await _yaPushDevice();
                        await _yaPushAF();

                        setState(() => _yaCurrentUrl = u.toString());

                        Future.delayed(const Duration(seconds: 20), () {
                          yaSendLoadedOnce(url: _yaCurrentUrl.toString(), timestart: _yaStartLoadTs);
                        });

                        if (mounted) setState(() => _yaBusyWheel = false);
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = action.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;

                        if (_yaIsBareMail(uri)) {
                          final mailto = _yaToMailto(uri);
                          await _yaOpenMailWeb(mailto);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final sch = uri.scheme.toLowerCase();

                        if (sch == 'mailto') {
                          await _yaOpenMailWeb(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (sch == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (_yaIsPlatformish(uri)) {
                          final web = _yaHttpize(uri);

                          final host = (web.host.isNotEmpty ? web.host : uri.host).toLowerCase();
                          final isSocial =
                              host.endsWith('x.com') ||
                                  host.endsWith('twitter.com') ||
                                  host.endsWith('facebook.com') ||
                                  host.startsWith('m.facebook.com') ||
                                  host.endsWith('instagram.com') ||
                                  host.endsWith('t.me') ||
                                  host.endsWith('telegram.me') ||
                                  host.endsWith('telegram.dog');

                          if (isSocial) {
                            await _yaOpenWeb(web.scheme == 'http' || web.scheme == 'https' ? web : uri);
                            return NavigationActionPolicy.CANCEL;
                          }

                          if (web.scheme == 'http' || web == uri) {
                            await _yaOpenWeb(web);
                          } else {
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else if (web != uri && (web.scheme == 'http' || web.scheme == 'https')) {
                                await _yaOpenWeb(web);
                              }
                            } catch (_) {}
                          }
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (sch != 'http' && sch != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (c, req) async {
                        final uri = req.request.url;
                        if (uri == null) return false;

                        if (_yaIsBareMail(uri)) {
                          final mailto = _yaToMailto(uri);
                          await _yaOpenMailWeb(mailto);
                          return false;
                        }

                        final sch = uri.scheme.toLowerCase();

                        if (sch == 'mailto') {
                          await _yaOpenMailWeb(uri);
                          return false;
                        }

                        if (sch == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return false;
                        }

                        if (_yaIsPlatformish(uri)) {
                          final web = _yaHttpize(uri);

                          final host = (web.host.isNotEmpty ? web.host : uri.host).toLowerCase();
                          final isSocial =
                              host.endsWith('x.com') ||
                                  host.endsWith('twitter.com') ||
                                  host.endsWith('facebook.com') ||
                                  host.startsWith('m.facebook.com') ||
                                  host.endsWith('instagram.com') ||
                                  host.endsWith('t.me') ||
                                  host.endsWith('telegram.me') ||
                                  host.endsWith('telegram.dog');

                          if (isSocial) {
                            await _yaOpenWeb(web.scheme == 'http' || web.scheme == 'https' ? web : uri);
                            return false;
                          }

                          if (web.scheme == 'http' || web.scheme == 'https') {
                            await _yaOpenWeb(web);
                          } else {
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else if (web != uri && (web.scheme == 'http' || web.scheme == 'https')) {
                                await _yaOpenWeb(web);
                              }
                            } catch (_) {}
                          }
                          return false;
                        }

                        if (sch == 'http' || sch == 'https') {
                          c.loadUrl(urlRequest: URLRequest(url: uri));
                        }
                        return false;
                      },
                      onDownloadStartRequest: (c, req) async {
                        await _yaOpenWeb(req.url);
                      },
                    ),
                    Visibility(
                      visible: !_yaVeil,
                      child: const JamKoruLoader(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SpiritCaptainDeck (вебвью для внешних ссылок)
// ============================================================================
class SpiritCaptainDeck extends StatefulWidget with WidgetsBindingObserver {
  final String seaLane;
  const SpiritCaptainDeck(this.seaLane, {super.key});

  @override
  State<SpiritCaptainDeck> createState() => _SpiritCaptainDeckState();
}

class _SpiritCaptainDeckState extends State<SpiritCaptainDeck> with WidgetsBindingObserver {
  late InAppWebViewController _deck;

  final Set<String> _schemes = {
    'tg', 'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
    'fb', 'instagram', 'twitter', 'x',
  };

  final Set<String> _externalHarbors = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com', 'www.bnl.com',
    'x.com', 'www.x.com',
    'twitter.com', 'www.twitter.com',
    'facebook.com', 'www.facebook.com', 'm.facebook.com',
    'instagram.com', 'www.instagram.com',
  };

  bool _bareMail(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  Uri _mailize(Uri u) {
    final full = u.toString();
    final parts = full.split('?');
    final email = parts.first;
    final qp = parts.length > 1 ? Uri.splitQueryString(parts[1]) : <String, String>{};
    return Uri(scheme: 'mailto', path: email, queryParameters: qp.isEmpty ? null : qp);
  }

  bool _platformish(Uri u) {
    final s = u.scheme.toLowerCase();
    if (_schemes.contains(s)) return true;

    if (s == 'http' || s == 'https') {
      final h = u.host.toLowerCase();
      if (_externalHarbors.contains(h)) return true;
      if (h.endsWith('t.me')) return true;
      if (h.endsWith('wa.me')) return true;
      if (h.endsWith('m.me')) return true;
      if (h.endsWith('signal.me')) return true;
      if (h.endsWith('x.com')) return true;
      if (h.endsWith('twitter.com')) return true;
      if (h.endsWith('facebook.com')) return true;
      if (h.endsWith('instagram.com')) return true;
    }
    return false;
  }

  Uri _httpize(Uri u) {
    final s = u.scheme.toLowerCase();

    if (s == 'tg' || s == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {if (qp['start'] != null) 'start': qp['start']!});
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if ((s == 'http' || s == 'https') && u.host.toLowerCase().endsWith('t.me')) {
      return u;
    }

    if (s == 'viber') return u;

    if (s == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${_digits(phone)}', {if (text != null && text.isNotEmpty) 'text': text});
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if ((s == 'http' || s == 'https') &&
        (u.host.toLowerCase().endsWith('wa.me') || u.host.toLowerCase().endsWith('whatsapp.com'))) {
      return u;
    }

    if (s == 'skype') return u;

    if (s == 'fb-messenger') {
      final path = u.pathSegments.isNotEmpty ? u.pathSegments.join('/') : '';
      final qp = u.queryParameters;
      final id = qp['id'] ?? qp['user'] ?? path;
      if (id.isNotEmpty) {
        return Uri.https('m.me', '/$id', u.queryParameters.isEmpty ? null : u.queryParameters);
      }
      return Uri.https('m.me', '/', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if (s == 'sgnl') {
      final qp = u.queryParameters;
      final ph = qp['phone'];
      final un = u.queryParameters['username'];
      if (ph != null && ph.isNotEmpty) return Uri.https('signal.me', '/#p/${_digits(ph)}');
      if (un != null && un.isNotEmpty) return Uri.https('signal.me', '/#u/$un');
      final path = u.pathSegments.join('/');
      if (path.isNotEmpty) return Uri.https('signal.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
      return u;
    }

    if (s == 'tel') {
      return Uri.parse('tel:${_digits(u.path)}');
    }

    if (s == 'mailto') return u;

    if (s == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if ((s == 'http' || s == 'https')) {
      final host = u.host.toLowerCase();
      if (host.endsWith('x.com') ||
          host.endsWith('twitter.com') ||
          host.endsWith('facebook.com') ||
          host.startsWith('m.facebook.com') ||
          host.endsWith('instagram.com')) {
        return u;
      }
    }

    if (s == 'fb' || s == 'instagram' || s == 'twitter' || s == 'x') {
      return u;
    }

    return u;
  }

  Future<bool> _openMailWeb(Uri mailto) async {
    final u = _gmailize(mailto);
    return await _openWeb(u);
  }

  Uri _gmailize(Uri m) {
    final qp = m.queryParameters;
    final params = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (m.path.isNotEmpty) 'to': m.path,
      if ((qp['subject'] ?? '').isNotEmpty) 'su': qp['subject']!,
      if ((qp['body'] ?? '').isNotEmpty) 'body': qp['body']!,
      if ((qp['cc'] ?? '').isNotEmpty) 'cc': qp['cc']!,
      if ((qp['bcc'] ?? '').isNotEmpty) 'bcc': qp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', params);
  }

  Future<bool> _openWeb(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openInAppBrowser error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  @override
  Widget build(BuildContext context) {
    final night = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            disableDefaultErrorPage: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            allowsPictureInPictureMediaPlayback: true,
            useOnDownloadStart: true,
            javaScriptCanOpenWindowsAutomatically: true,
            useShouldOverrideUrlLoading: true,
            supportMultipleWindows: true,
          ),
          initialUrlRequest: URLRequest(url: WebUri(widget.seaLane)),
          onWebViewCreated: (c) => _deck = c,
          onLoadStart: (c, u) {},
        ),
      ),
    );
  }
}

// ============================================================================
// Help экраны
// ============================================================================
class PirateHelp extends StatefulWidget {
  const PirateHelp({super.key});

  @override
  State<PirateHelp> createState() => _PirateHelpState();
}

class _PirateHelpState extends State<PirateHelp> with WidgetsBindingObserver {
  InAppWebViewController? _ctrl;
  bool _spin = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              initialFile: 'assets/index.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: false,
                disableHorizontalScroll: false,
                disableVerticalScroll: false,
              ),
              onWebViewCreated: (c) => _ctrl = c,
              onLoadStart: (c, u) => setState(() => _spin = true),
              onLoadStop: (c, u) async => setState(() => _spin = false),
              onLoadError: (c, u, code, msg) => setState(() => _spin = false),
            ),
            if (_spin) const JamKoruLoader(),
          ],
        ),
      ),
    );
  }
}

class PirateHelpLite extends StatefulWidget {
  const PirateHelpLite({super.key});

  @override
  State<PirateHelpLite> createState() => _PirateHelpLiteState();
}

class _PirateHelpLiteState extends State<PirateHelpLite> {
  InAppWebViewController? _wvc;
  bool _ld = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialFile: 'assets/dream.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: false,
                disableHorizontalScroll: false,
                disableVerticalScroll: false,
                transparentBackground: true,
                mediaPlaybackRequiresUserGesture: false,
                disableDefaultErrorPage: true,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
              ),
              onWebViewCreated: (controller) => _wvc = controller,
              onLoadStart: (controller, url) => setState(() => _ld = true),
              onLoadStop: (controller, url) async => setState(() => _ld = false),
              onLoadError: (controller, url, code, message) => setState(() => _ld = false),
            ),
            if (_ld)
              const Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: JamKoruLoader(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// main()
// ============================================================================
