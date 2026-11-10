import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'supabase_config.dart';
import 'utils/tap_guard.dart';
import 'services/address_service.dart';
import 'services/notification_service.dart';
import 'services/push_router.dart';
import 'screens/loading_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      // Bilah navigasi Android (bawah) dibuat terang agar menyatu dengan aplikasi
      systemNavigationBarColor: Color(0xFFF8FAFC),
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Inisialisasi Firebase & Push Notification
  try {
    await Firebase.initializeApp();
    PushRouter.attach(appNavigatorKey);
    await NotificationService().initialize(onTapped: PushRouter.handle);
    PushRouter.listenAuth();
  } catch (e) {
    // Firebase mungkin belum setup di web/desktop, diabaikan
  }

  await AddressService.init();

  // Link "Reset Password" dari email membuka aplikasi dengan sesi pemulihan:
  // arahkan pengguna ke layar buat password baru.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event != AuthChangeEvent.passwordRecovery) return;
    final nav = appNavigatorKey.currentState;
    if (PasswordRecovery.appReady && nav != null) {
      nav.push(MaterialPageRoute(builder: (_) => const ForgotPasswordScreen(fromRecoveryLink: true)));
    } else {
      PasswordRecovery.pending = true; // dibuka oleh layar pembuka
    }
  });

  runApp(const MyApp());
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Washora',
      navigatorKey: appNavigatorKey,
      navigatorObservers: [NavTapShield.instance],
      debugShowCheckedModeBanner: false,
      // Izinkan geser (carousel, list horizontal) dengan mouse & trackpad di web/desktop
      // Warna bilah navigasi Android untuk semua layar (layar yang punya
      // pengaturan sendiri di bagian bawah tetap bisa menimpanya)
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Color(0xFFF8FAFC),
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: NavTapShield.wrap(child ?? const SizedBox.shrink()),
      ),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: PointerDeviceKind.values.toSet(),
      ),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0077E6),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(
          ThemeData.light().textTheme,
        ),
      ),
      home: const LoadingScreen(),
    );
  }
}
