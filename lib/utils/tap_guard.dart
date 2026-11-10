import 'dart:async';

import 'package:flutter/widgets.dart';

/// Mencegah tombol/menu terbuka dua kali karena diketuk cepat berulang
/// (double tap), terutama saat internet lambat dan halaman memuat data dulu.
class TapGuard {
  TapGuard._();

  static bool _busy = false;
  static const _cooldown = Duration(milliseconds: 600);

  /// Jalankan [action] hanya jika tidak ada aksi lain yang sedang berjalan.
  /// Ketukan berikutnya diabaikan sampai [action] selesai + jeda singkat.
  static Future<void> run(FutureOr<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } finally {
      Timer(_cooldown, () => _busy = false);
    }
  }

  /// Bungkus callback onTap: `onTap: TapGuard.wrap(_openSomething)`.
  static VoidCallback wrap(FutureOr<void> Function() action) => () => run(action);
}

/// Pengaman global: selama animasi pindah halaman / munculnya sheet & dialog,
/// ketukan ke layar diabaikan, sehingga ketukan kedua dari double tap tidak
/// membuka halaman yang sama lagi.
class NavTapShield extends NavigatorObserver {
  NavTapShield._();
  static final instance = NavTapShield._();

  final absorbing = ValueNotifier<bool>(false);
  Timer? _timer;

  void _hold() {
    absorbing.value = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 450), () => absorbing.value = false);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Rute pertama aplikasi tidak perlu ditahan
    if (previousRoute != null) _hold();
  }

  /// Dipasang di MaterialApp.builder
  static Widget wrap(Widget child) => ValueListenableBuilder<bool>(
        valueListenable: instance.absorbing,
        builder: (_, absorbing, c) => AbsorbPointer(absorbing: absorbing, child: c),
        child: child,
      );
}
