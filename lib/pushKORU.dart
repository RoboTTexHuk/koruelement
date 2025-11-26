// -----------------------------------------------------------------------------
// YaMistic refactor: все классы и переменные переименованы в ямайском стиле
// -----------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart' show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если ваш проект ссылается на эти имена — см. алиасы в самом конце файла
// import 'main.dart' show SpiritMafiaHarbor, SpiritCaptainHarbor, CaptainHarbor, CaptainDeck;

// ============================================================================
// Jam утилиты/инфраструктура (irie edition)
// ============================================================================

class JamBlackBox {
  const JamBlackBox();
  void yaLog(Object msg) => debugPrint('[JamBlackBox] $msg');
  void yaWarn(Object msg) => debugPrint('[JamBlackBox/WARN] $msg');
  void yaErr(Object msg) => debugPrint('[JamBlackBox/ERR] $msg');
}

class JamRumChest {
  static final JamRumChest _oneLove = JamRumChest._irie();
  JamRumChest._irie();
  factory JamRumChest() => _oneLove;

  final JamBlackBox yaBox = const JamBlackBox();
}

// ============================================================================
// Пиратский секстант: почта/маршруты/цифры
// ============================================================================
class JamSextant {
  // Bare e-mail без схемы
  static bool yaLooksLikeBareMail(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  // Превращаем сырой адрес или URL в mailto:
  static Uri yaToMailto(Uri u) {
    final full = u.toString();
    final bits = full.split('?');
    final who = bits.first;
    final qp = bits.length > 1 ? Uri.splitQueryString(bits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: who,
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  // Gmail compose
  static Uri yaGmailize(Uri mailto) {
    final qp = mailto.queryParameters;
    final params = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (mailto.path.isNotEmpty) 'to': mailto.path,
      if ((qp['subject'] ?? '').isNotEmpty) 'su': qp['subject']!,
      if ((qp['body'] ?? '').isNotEmpty) 'body': qp['body']!,
      if ((qp['cc'] ?? '').isNotEmpty) 'cc': qp['cc']!,
      if ((qp['bcc'] ?? '').isNotEmpty) 'bcc': qp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', params);
  }

  static String yaDigits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// JamParrotSignal — открытие внешних ссылок/протоколов
// ============================================================================
class JamParrotSignal {
  static Future<bool> yaOpen(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('JamParrotSignal error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// Лоадер: зелёный неон “KORU” на чёрном, джунглевое свечение
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
      begin: const Color(0xFF00FF66),
      end: const Color(0xFF9BFF00),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  IgnorePointer(
                    child: Container(
                      width: 320,
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.4),
                          radius: 1.0,
                          colors: [c.withOpacity(0.16), Colors.transparent],
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
// FCM Background Handler — ya-parrot
// ============================================================================
@pragma('vm:entry-point')
Future<void> yaBgParrot(RemoteMessage yaBottle) async {
  debugPrint("Ya Bottle ID: ${yaBottle.messageId}");
  debugPrint("Ya Bottle Data: ${yaBottle.data}");
}

// ============================================================================
// JamCaptainDeck — экран с WebView
// ============================================================================
class JamCaptainDeck extends StatefulWidget with WidgetsBindingObserver {
  String yaSeaLane;
  JamCaptainDeck(this.yaSeaLane, {super.key});

  @override
  State<JamCaptainDeck> createState() => _JamCaptainDeckState(yaSeaLane);
}

class _JamCaptainDeckState extends State<JamCaptainDeck> with WidgetsBindingObserver {
  _JamCaptainDeckState(this._yaCurrentLane);

  final JamRumChest _rum = JamRumChest();

  late InAppWebViewController _helm; // штурвал
  String? _parrot; // FCM token
  String? _shipId; // device id
  String? _shipBuild; // os build
  String? _shipKind; // android/ios
  String? _shipLang; // locale/lang
  String? _shipTz; // timezone
  bool _pushOn = true; // push enabled
  bool _crewBusy = false;
  String _yaCurrentLane;
  DateTime? _lastDockTime;

  // Внешние гавани (tg/wa/bnl)
  final Set<String> _outerHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'bnl.com', 'www.bnl.com',
  };
  final Set<String> _outerSchemes = {'tg', 'telegram', 'whatsapp', 'bnl'};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(yaBgParrot);

    _rigParrotFCM();
    _scanShipGizmo();
    _wireForedeckFCM();
    _bindBell();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState tide) {
    if (tide == AppLifecycleState.paused) {
      _lastDockTime = DateTime.now();
    }
    if (tide == AppLifecycleState.resumed) {
      if (Platform.isIOS && _lastDockTime != null) {
        final now = DateTime.now();
        final drift = now.difference(_lastDockTime!);
        if (drift > const Duration(minutes: 25)) {
          _hardReloadToHarbor();
        }
      }
      _lastDockTime = null;
    }
  }

  void _hardReloadToHarbor() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => JamCaptainHarbor(signal: "")),
            (route) => false,
      );
    });
  }

  // --------------------------------------------------------------------------
  // Каналы связи
  // --------------------------------------------------------------------------
  void _wireForedeckFCM() {
    FirebaseMessaging.onMessage.listen((RemoteMessage bottle) {
      if (bottle.data['uri'] != null) {
        _sailTo(bottle.data['uri'].toString());
      } else {
        _returnToCourse();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage bottle) {
      if (bottle.data['uri'] != null) {
        _sailTo(bottle.data['uri'].toString());
      } else {
        _returnToCourse();
      }
    });
  }

  void _sailTo(String lane) async {
    await _helm.loadUrl(urlRequest: URLRequest(url: WebUri(lane)));
  }

  void _returnToCourse() async {
    Future.delayed(const Duration(seconds: 3), () {
      _helm.loadUrl(urlRequest: URLRequest(url: WebUri(_yaCurrentLane)));
    });
  }

  Future<void> _rigParrotFCM() async {
    FirebaseMessaging deck = FirebaseMessaging.instance;
    await deck.requestPermission(alert: true, badge: true, sound: true);
    _parrot = await deck.getToken();
  }

  // --------------------------------------------------------------------------
  // Досье корабля
  // --------------------------------------------------------------------------
  Future<void> _scanShipGizmo() async {
    try {
      final spy = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await spy.androidInfo;
        _shipId = a.id;
        _shipKind = "android";
        _shipBuild = a.version.release;
      } else if (Platform.isIOS) {
        final i = await spy.iosInfo;
        _shipId = i.identifierForVendor;
        _shipKind = "ios";
        _shipBuild = i.systemVersion;
      }
      final pkg = await PackageInfo.fromPlatform();
      _shipLang = Platform.localeName.split('_')[0];
      _shipTz = timezone.local.name;
    } catch (e) {
      debugPrint("Ya Ship Gizmo Error: $e");
    }
  }

  void _bindBell() {
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

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    _bindBell(); // повторная привязка

    final isNight = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isNight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
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
              initialUrlRequest: URLRequest(url: WebUri(_yaCurrentLane)),
              onWebViewCreated: (controller) {
                _helm = controller;

                _helm.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    _rum.yaBox.yaLog("JS Args: $args");
                    try {
                      return args.reduce((v, e) => v + e);
                    } catch (_) {
                      return args.toString();
                    }
                  },
                );
              },
              onLoadStart: (controller, uri) async {
                if (uri != null) {
                  if (JamSextant.yaLooksLikeBareMail(uri)) {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                    final mailto = JamSextant.yaToMailto(uri);
                    await JamParrotSignal.yaOpen(JamSextant.yaGmailize(mailto));
                    return;
                  }
                  final s = uri.scheme.toLowerCase();
                  if (s != 'http' && s != 'https') {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (controller, uri) async {
                await controller.evaluateJavascript(source: "console.log('Irie JS ready!');");
              },
              shouldOverrideUrlLoading: (controller, nav) async {
                final uri = nav.request.url;
                if (uri == null) return NavigationActionPolicy.ALLOW;

                if (JamSextant.yaLooksLikeBareMail(uri)) {
                  final mailto = JamSextant.yaToMailto(uri);
                  await JamParrotSignal.yaOpen(JamSextant.yaGmailize(mailto));
                  return NavigationActionPolicy.CANCEL;
                }

                final sch = uri.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await JamParrotSignal.yaOpen(JamSextant.yaGmailize(uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (_isOuterHarbor(uri)) {
                  await JamParrotSignal.yaOpen(_mapOuterToHttp(uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (sch != 'http' && sch != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (controller, req) async {
                final u = req.request.url;
                if (u == null) return false;

                if (JamSextant.yaLooksLikeBareMail(u)) {
                  final m = JamSextant.yaToMailto(u);
                  await JamParrotSignal.yaOpen(JamSextant.yaGmailize(m));
                  return false;
                }

                final sch = u.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await JamParrotSignal.yaOpen(JamSextant.yaGmailize(u));
                  return false;
                }

                if (_isOuterHarbor(u)) {
                  await JamParrotSignal.yaOpen(_mapOuterToHttp(u));
                  return false;
                }

                if (sch == 'http' || sch == 'https') {
                  controller.loadUrl(urlRequest: URLRequest(url: u));
                }
                return false;
              },
            ),

            if (_crewBusy)
              const Positioned.fill(
                child: IgnorePointer(
                  child: JamKoruLoader(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Маршрутизация внешних протоколов/гаваней
  // ========================================================================
  bool _isOuterHarbor(Uri u) {
    final sch = u.scheme.toLowerCase();
    if (_outerSchemes.contains(sch)) return true;

    if (sch == 'http' || sch == 'https') {
      final h = u.host.toLowerCase();
      if (_outerHosts.contains(h)) return true;
    }
    return false;
  }

  Uri _mapOuterToHttp(Uri u) {
    final sch = u.scheme.toLowerCase();

    if (sch == 'tg' || sch == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {
          if (qp['start'] != null) 'start': qp['start']!,
        });
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', qp.isEmpty ? null : qp);
    }

    if (sch == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${JamSextant.yaDigits(phone)}', {
          if (text != null && text.isNotEmpty) 'text': text,
        });
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if (sch == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    return u;
  }
}

// ============================================================================
// JamCaptainHarbor — точка входа с WebView и лоадером KORU
// ============================================================================
class JamCaptainHarbor extends StatefulWidget {
  final String? signal;
  const JamCaptainHarbor({super.key, required this.signal});

  @override
  State<JamCaptainHarbor> createState() => _JamCaptainHarborState();
}

class _JamCaptainHarborState extends State<JamCaptainHarbor> {
  bool _cover = true;
  final String _home = "https://spp.spiritinmydream.online/";
  late InAppWebViewController _pier;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _cover = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          InAppWebView(
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
            initialUrlRequest: URLRequest(url: WebUri(_home)),
            onWebViewCreated: (c) => _pier = c,
          ),
          if (_cover) const JamKoruLoader(),
        ],
      ),
    );
  }
}

// ============================================================================
// JamMafiaHarbor — стартовый экран, инициализация Firebase, таймзоны, FCM
// ============================================================================
class JamMafiaHarbor extends StatefulWidget {
  const JamMafiaHarbor({super.key});

  @override
  State<JamMafiaHarbor> createState() => _JamMafiaHarborState();
}

class _JamMafiaHarborState extends State<JamMafiaHarbor> {
  bool _ready = false;
  String? _signal;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp();
      timezone_data.initializeTimeZones();
      FirebaseMessaging.onBackgroundMessage(yaBgParrot);

      final parrot = await FirebaseMessaging.instance.getToken();
      _signal = parrot ?? "";

      setState(() => _ready = true);
    } catch (e) {
      debugPrint("Jam boot err: $e");
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(backgroundColor: Colors.black, body: JamKoruLoader());
    }
    return JamCaptainHarbor(signal: _signal);
  }
}

// ============================================================================
// main()
// ============================================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  timezone_data.initializeTimeZones();
  FirebaseMessaging.onBackgroundMessage(yaBgParrot);

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: JamMafiaHarbor(),
  ));
}

// ============================================================================
// Совместимость с прежними именами (если где-то есть импорты/ссылки):
// SpiritMafiaHarbor -> JamMafiaHarbor
// SpiritCaptainHarbor/CaptainHarbor -> JamCaptainHarbor
// CaptainDeck -> JamCaptainDeck
// ============================================================================
typedef SpiritMafiaHarbor = JamMafiaHarbor;
typedef SpiritCaptainHarbor = JamCaptainHarbor;
typedef CaptainHarbor = JamCaptainHarbor;
typedef CaptainDeck = JamCaptainDeck;