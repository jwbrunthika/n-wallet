import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class PortraitCameraViewport extends StatelessWidget {
  const PortraitCameraViewport({
    super.key,
    required this.controller,
    required this.child,
    this.overlayOpacity = 0.2,
  });

  final CameraController controller;
  final Widget child;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const frameAspectRatio = 0.74;
        final frameWidth = math.min(
          constraints.maxWidth,
          constraints.maxHeight * frameAspectRatio,
        );
        final frameHeight = frameWidth / frameAspectRatio;

        return Center(
          child: SizedBox(
            width: frameWidth,
            height: frameHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CameraPreviewCover(controller: controller),
                  Container(
                    color: Colors.black.withValues(alpha: overlayOpacity),
                  ),
                  child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CameraPreviewCover extends StatelessWidget {
  const _CameraPreviewCover({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
