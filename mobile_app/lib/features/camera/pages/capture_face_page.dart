import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/shared/camera/camera_registry.dart';
import 'package:mobile_app/shared/camera/portrait_camera_viewport.dart';

class CaptureFacePage extends StatefulWidget {
  const CaptureFacePage({super.key});

  @override
  State<CaptureFacePage> createState() => _CaptureFacePageState();
}

class _CaptureFacePageState extends State<CaptureFacePage> {
  CameraController? controller;
  bool initializing = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameraLoadError = await ensureCamerasLoaded();
    if (cameraLoadError != null) {
      setState(() {
        initializing = false;
        error = cameraLoadError;
      });
      return;
    }

    final selected = gCameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => gCameras.first,
    );

    final cameraController = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await cameraController.initialize();
      setState(() {
        controller = cameraController;
        initializing = false;
      });
    } catch (e) {
      setState(() {
        initializing = false;
        error = 'Unable to initialize camera: $e';
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Capture Face')),
        body: Center(child: Text(error!)),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: Get.back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Capture Face',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 42),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PortraitCameraViewport(
                  controller: controller!,
                  overlayOpacity: 0.2,
                  child: Center(
                    child: Container(
                      width: 304,
                      height: 304,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              child: SizedBox(
                width: 94,
                height: 94,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 94,
                      height: 94,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          width: 5,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        final file = await controller!.takePicture();
                        if (!mounted) return;
                        Get.back(result: file.path);
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
