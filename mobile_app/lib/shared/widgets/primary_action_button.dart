import 'package:flutter/material.dart';
import 'package:mobile_app/app/app_colors.dart';

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.text,
    this.icon,
    required this.onPressed,
    this.busy = false,
    this.disabledColor,
  });

  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Color? disabledColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: disabledColor ?? const Color(0xFFB7C2D1),
          foregroundColor: Colors.white,
          elevation: enabled ? 7 : 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.2),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 22),
                  ],
                ],
              ),
      ),
    );
  }
}
