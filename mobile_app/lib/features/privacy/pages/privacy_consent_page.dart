import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/shared/widgets/primary_action_button.dart';

class PrivacyConsentPage extends StatefulWidget {
  const PrivacyConsentPage({super.key});

  @override
  State<PrivacyConsentPage> createState() => _PrivacyConsentPageState();
}

class _PrivacyConsentPageState extends State<PrivacyConsentPage> {
  bool consentChecked = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: Get.back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Privacy & Consent',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF004D35), Color(0xFF11804A)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 94),
                        const Row(
                          children: [
                            Icon(Icons.warning, color: Color(0xFFFFE082)),
                            SizedBox(width: 8),
                            Text(
                              'ACTION REQUIRED',
                              style: TextStyle(
                                color: Color(0xFFFFE082),
                                letterSpacing: 1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Pending Review',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please review the data collection policies below to verify your identity for university attendance.',
                          style: TextStyle(
                            color: Color(0xFFE2F4EA),
                            fontSize: 22,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'DATA COLLECTION POLICIES',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _policyExpansion(
                    icon: Icons.face,
                    title: 'Biometric Data (Face ID)',
                    body:
                        'Your facial data is cryptographically hashed and used solely for attendance verification. Images are processed locally and matched against the university\'s secure database. No raw facial data is shared with third parties.',
                    initiallyExpanded: true,
                  ),
                  _policyExpansion(
                    icon: Icons.location_on,
                    title: 'Location Verification (iBeacon)',
                    body:
                        'Bluetooth Low Energy iBeacon signals are used only at the attendance check moment to verify hall presence. Continuous location tracking is not performed.',
                  ),
                  _policyExpansion(
                    icon: Icons.description,
                    title: 'Audit Logs & Data Retention',
                    body:
                        'Attendance and admin access logs are retained for auditing and academic compliance. Access is restricted to authorized staff.',
                  ),
                  const SizedBox(height: 20),
                  const Center(
                    child: Text(
                      'ACCOUNT MANAGEMENT',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _outlineAction(
                    icon: Icons.refresh,
                    text: 'Request Re-enrollment',
                    color: AppColors.textSecondary,
                    onTap: () => Get.snackbar(
                      'Submitted',
                      'Your re-enrollment request has been logged.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _outlineAction(
                    icon: Icons.delete,
                    text: 'Request Account Deletion',
                    color: AppColors.danger,
                    onTap: () => Get.snackbar(
                      'Submitted',
                      'Your account deletion request has been logged.',
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: consentChecked,
                        onChanged: (value) =>
                            setState(() => consentChecked = value ?? false),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'I have read and agree to the data collection policies regarding my biometric and location data.',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 19,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PrimaryActionButton(
                    text: 'Confirm & Continue',
                    icon: Icons.arrow_forward,
                    onPressed: consentChecked
                        ? () {
                            Get.back();
                            Get.snackbar(
                              'Consent saved',
                              'Your privacy consent is confirmed.',
                            );
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _policyExpansion({
    required IconData icon,
    required String title,
    required String body,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE5ECE8),
              borderRadius: BorderRadius.circular(19),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 19,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Text(
              body,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 17,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlineAction({
    required IconData icon,
    required String text,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
