import 'package:flutter/material.dart';
import 'partner/partner_home_screen.dart';

// OwnerDashboardScreen now acts as a redirect shell to PartnerHomeScreen.
// All partner logic lives in lib/screens/partner/.
class OwnerDashboardScreen extends StatelessWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Redirect immediately to the full partner home screen.
    return const PartnerHomeScreen();
  }
}
