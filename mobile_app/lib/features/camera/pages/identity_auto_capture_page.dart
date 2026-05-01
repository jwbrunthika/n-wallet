import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/shared/camera/camera_mlkit.dart';
import 'package:mobile_app/shared/camera/camera_registry.dart';
import 'package:mobile_app/shared/camera/portrait_camera_viewport.dart';
import 'package:mobile_app/shared/widgets/primary_action_button.dart';

class IdentityAutoCapturePage extends StatefulWidget {
  const IdentityAutoCapturePage({super.key});

  @override
  State<IdentityAutoCapturePage> createState() =>
      _IdentityAutoCapturePageState();
}

class _IdentityAutoCapturePageState extends State<IdentityAutoCapturePage> {
  late final FaceDetector faceDetector;

  CameraController? controller;
  bool initializing = true;
  bool streaming = false;
  bool processingFrame = false;
  bool capturing = false;
  String? error;
  String guidanceTitle = 'Look straight ahead';
  String guidanceMessage =
      'Keep your face inside the circle. The photo will be captured automatically.';

  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _stableMatchCount = 0;

  @override
  void initState() {
    super.initState();
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableTracking: true,
        minFaceSize: 0.15,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
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
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.nv21,
    );

    try {
      await cameraController.initialize();
      if (!cameraController.supportsImageStreaming()) {
        throw CameraException(
          'image-streaming-unavailable',
          'Live face detection is not supported on this device.',
        );
      }

      if (!mounted) {
        await cameraController.dispose();
        return;
      }

      setState(() {
        controller = cameraController;
        initializing = false;
        error = null;
      });
      await _startImageStream();
    } catch (e) {
      await cameraController.dispose();
      if (!mounted) return;
      setState(() {
        initializing = false;
        error = 'Unable to start auto capture: $e';
      });
    }
  }

  Future<void> _startImageStream() async {
    final cameraController = controller;
    if (cameraController == null || streaming || !mounted) return;
    await cameraController.startImageStream(_processCameraImage);
    streaming = true;
  }

  Future<void> _stopImageStream() async {
    final cameraController = controller;
    if (cameraController == null || !streaming) return;
    try {
      await cameraController.stopImageStream();
    } catch (_) {
      // Ignore stop failures during page transitions or dispose.
    } finally {
      streaming = false;
    }
  }

  Future<void> _retryCamera() async {
    final oldController = controller;
    controller = null;
    if (oldController != null) {
      await _stopImageStream();
      await oldController.dispose();
    }
    if (!mounted) return;
    setState(() {
      initializing = true;
      error = null;
      _stableMatchCount = 0;
      guidanceTitle = 'Look straight ahead';
      guidanceMessage =
          'Keep your face inside the circle. The photo will be captured automatically.';
    });
    await _initCamera();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted || capturing || processingFrame || error != null) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessedAt) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastProcessedAt = now;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;

    processingFrame = true;
    try {
      final faces = await faceDetector.processImage(inputImage);
      if (!mounted || capturing) return;
      _handleFaces(faces, inputImage.metadata!.size);
    } catch (_) {
      // Keep the preview alive if one frame fails to process.
    } finally {
      processingFrame = false;
    }
  }

  void _handleFaces(List<Face> faces, Size imageSize) {
    if (faces.isEmpty) {
      _stableMatchCount = 0;
      _setGuidance(
        'Find your face',
        'Place your full face inside the circle so we can verify you.',
      );
      return;
    }

    if (faces.length > 1) {
      _stableMatchCount = 0;
      _setGuidance(
        'One person only',
        'Make sure only your face is visible in the frame.',
      );
      return;
    }

    final face = faces.first;
    if (!_isFaceAligned(face, imageSize)) {
      _stableMatchCount = 0;
      return;
    }

    if (!_isFaceFrontal(face)) {
      _stableMatchCount = 0;
      _setGuidance(
        'Face the camera',
        'Look straight ahead and keep your head level for a quick capture.',
      );
      return;
    }

    _stableMatchCount += 1;
    if (_stableMatchCount < 2) {
      _setGuidance(
        'Hold still',
        'Stay steady for a moment while we capture your photo.',
      );
      return;
    }

    unawaited(_capturePhoto());
  }

  bool _isFaceAligned(Face face, Size imageSize) {
    final bounds = face.boundingBox;
    final widthRatio = bounds.width / imageSize.width;
    final heightRatio = bounds.height / imageSize.height;
    final centerX = bounds.center.dx / imageSize.width;
    final centerY = bounds.center.dy / imageSize.height;

    if (widthRatio < 0.15 || heightRatio < 0.17) {
      _setGuidance(
        'Move closer',
        'Bring your face a little closer until it fills more of the guide.',
      );
      return false;
    }

    if (widthRatio > 0.74 || heightRatio > 0.84) {
      _setGuidance(
        'Move back slightly',
        'Keep your full face visible inside the circle.',
      );
      return false;
    }

    if (centerX < 0.24 || centerX > 0.76 || centerY < 0.16 || centerY > 0.80) {
      _setGuidance(
        'Center your face',
        'Keep your face inside the circle and look directly at the camera.',
      );
      return false;
    }

    return true;
  }

  bool _isFaceFrontal(Face face) {
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX ?? 0;
    final roll = face.headEulerAngleZ ?? 0;

    if (yaw == null) return false;
    return yaw.abs() <= kFrontYawMax && pitch.abs() <= 18 && roll.abs() <= 15;
  }

  Future<void> _capturePhoto() async {
    final cameraController = controller;
    if (cameraController == null || capturing) return;

    setState(() {
      capturing = true;
      _stableMatchCount = 0;
    });
    _setGuidance('Capturing photo', 'Hold still while we save the image.');

    try {
      await _stopImageStream();
      final photo = await cameraController.takePicture();
      if (!mounted) return;
      Get.back(result: photo.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        capturing = false;
        error = 'Automatic capture failed: $e';
      });
    }
  }

  void _setGuidance(String title, String message) {
    if (!mounted) return;
    if (guidanceTitle == title && guidanceMessage == message) return;
    setState(() {
      guidanceTitle = title;
      guidanceMessage = message;
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final cameraController = controller;
    if (cameraController == null) return null;

    final rotation = _inputRotationFromCamera(cameraController);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _inputRotationFromCamera(
    CameraController cameraController,
  ) {
    final sensorOrientation = cameraController.description.sensorOrientation;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (!Platform.isAndroid) return null;

    var compensation =
        kCameraOrientations[cameraController.value.deviceOrientation];
    if (compensation == null) return null;

    if (cameraController.description.lensDirection ==
        CameraLensDirection.front) {
      compensation = (sensorOrientation + compensation) % 360;
    } else {
      compensation = (sensorOrientation - compensation + 360) % 360;
    }

    return InputImageRotationValue.fromRawValue(compensation);
  }

  @override
  void dispose() {
    final activeController = controller;
    if (activeController != null && activeController.value.isStreamingImages) {
      unawaited(activeController.stopImageStream().catchError((_) {}));
    }
    activeController?.dispose();
    unawaited(faceDetector.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verify Your Identity')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                PrimaryActionButton(
                  text: 'Retry Camera',
                  onPressed: _retryCamera,
                ),
              ],
            ),
          ),
        ),
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
                      'Verify Your Identity',
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
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(
                'Look straight ahead. Your face photo will be captured automatically.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PortraitCameraViewport(
                  controller: controller!,
                  overlayOpacity: 0.22,
                  child: Center(
                    child: Container(
                      width: 308,
                      height: 308,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: capturing ? AppColors.success : Colors.white,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            capturing
                                ? Icons.photo_camera
                                : Icons.face_retouching_natural,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                guidanceTitle,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                guidanceMessage,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Use good lighting and keep only your face in the frame.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
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
