import 'dart:async';

import 'package:flutter/material.dart';

/// Durasi standar snackbar di seluruh aplikasi.
const Duration kSnackBarDuration = Duration(milliseconds: 2500);

extension QuickSnackBar on ScaffoldMessengerState {
  /// Menampilkan snackbar yang selalu hilang otomatis setelah [duration],
  /// termasuk snackbar yang memiliki tombol aksi (yang secara bawaan Flutter
  /// tidak akan hilang sendiri). Snackbar sebelumnya langsung diganti.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showQuickSnackBar(
    SnackBar snackBar, {
    Duration duration = kSnackBarDuration,
  }) {
    removeCurrentSnackBar();
    final controller = showSnackBar(snackBar);
    var closed = false;
    controller.closed.then((_) => closed = true);
    Timer(duration, () {
      if (!closed && mounted) controller.close();
    });
    return controller;
  }
}
