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

enum _EnrollmentCaptureStage { front, firstSide, oppositeSide }

const double kFrontYawMax = 10;
const double kSideYawMin = 12;

class EnrollmentAutoCapturePage extends StatefulWidget {
  const EnrollmentAutoCapturePage({super.key});

  @override
  State<EnrollmentAutoCapturePage> createState() =>
      _EnrollmentAutoCapturePageState();
}

class _EnrollmentAutoCapturePageState extends State<EnrollmentAutoCapturePage> {
  late final FaceDetector faceDetector;

  CameraController? controller;
  final List<String> capturedPaths = <String>[];

  bool initializing = true;
  bool streaming = false;
  bool processingFrame = false;
  bool capturing = false;
  String? error;
  String guidanceTitle = 'Look straight ahead';
  String guidanceMessage = 'Hold still while we detect your face.';

  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _stableMatchCount = 0;
  int? _firstSideSign;

  _EnrollmentCaptureStage get _currentStage {
    switch (capturedPaths.length) {
      case 0:
        return _EnrollmentCaptureStage.front;
      case 1:
        return _EnrollmentCaptureStage.firstSide;
      default:
        return _EnrollmentCaptureStage.oppositeSide;
    }
  }

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
      _updateGuidanceForCurrentStage();
      await _startImageStream();
    } catch (e) {
      await cameraController.dispose();
      if (!mounted) return;
      setState(() {
        initializing = false;
        error = 'Unable to start guided capture: $e';
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

  Future<void> _restartScan() async {
    if (capturing) return;
    setState(() {
      capturedPaths.clear();
      _firstSideSign = null;
      _stableMatchCount = 0;
    });
    _updateGuidanceForCurrentStage();
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
      capturedPaths.clear();
      _firstSideSign = null;
      _stableMatchCount = 0;
    });
    await _initCamera();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted || capturing || processingFrame || error != null) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessedAt) < const Duration(milliseconds: 350)) {
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
        'Place your full face inside the circle so the scan can begin.',
      );
      return;
    }

    if (faces.length > 1) {
      _stableMatchCount = 0;
      _setGuidance(
        'One person only',
        'Make sure only one face is visible in the camera view.',
      );
      return;
    }

    final face = faces.first;
    if (!_isFaceAligned(face, imageSize)) {
      _stableMatchCount = 0;
      return;
    }

    if (!_matchesCurrentStage(face)) {
      _stableMatchCount = 0;
      _updateGuidanceForCurrentStage();
      return;
    }

    _stableMatchCount += 1;
    if (_stableMatchCount < 2) {
      _setGuidance(
        'Hold still',
        'Stay steady for a moment while we capture this angle.',
      );
      return;
    }

    unawaited(_captureCurrentStage(face));
  }

  bool _isFaceAligned(Face face, Size imageSize) {
    final bounds = face.boundingBox;
    final widthRatio = bounds.width / imageSize.width;
    final heightRatio = bounds.height / imageSize.height;
    final centerX = bounds.center.dx / imageSize.width;
    final centerY = bounds.center.dy / imageSize.height;
    final isSideStage = _currentStage != _EnrollmentCaptureStage.front;
    final minWidthRatio = isSideStage ? 0.13 : 0.18;
    final minHeightRatio = isSideStage ? 0.15 : 0.18;
    final minCenterX = isSideStage ? 0.20 : 0.28;
    final maxCenterX = isSideStage ? 0.80 : 0.72;

    if (widthRatio < minWidthRatio || heightRatio < minHeightRatio) {
      _setGuidance(
        'Move closer',
        'Bring your face a little closer until it fills more of the circle.',
      );
      return false;
    }

    if (widthRatio > 0.68 || heightRatio > 0.82) {
      _setGuidance(
        'Move back slightly',
        'Keep your full face visible inside the guide.',
      );
      return false;
    }

    if (centerX < minCenterX ||
        centerX > maxCenterX ||
        centerY < 0.16 ||
        centerY > 0.80) {
      _setGuidance(
        'Center your face',
        isSideStage
            ? 'Keep your face inside the circle while you turn.'
            : 'Keep your face inside the circle and look directly at the camera.',
      );
      return false;
    }

    return true;
  }

  bool _matchesCurrentStage(Face face) {
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX ?? 0;
    final roll = face.headEulerAngleZ ?? 0;
    final isSideStage = _currentStage != _EnrollmentCaptureStage.front;

    if (yaw == null ||
        pitch.abs() > (isSideStage ? 24 : 18) ||
        roll.abs() > (isSideStage ? 20 : 15)) {
      return false;
    }

    switch (_currentStage) {
      case _EnrollmentCaptureStage.front:
        return yaw.abs() <= kFrontYawMax;
      case _EnrollmentCaptureStage.firstSide:
        return yaw.abs() >= kSideYawMin;
      case _EnrollmentCaptureStage.oppositeSide:
        final sign = _sideSignForYaw(yaw);
        return sign != null &&
            _firstSideSign != null &&
            sign != _firstSideSign &&
            yaw.abs() >= kSideYawMin;
    }
  }

  int? _sideSignForYaw(double? yaw) {
    if (yaw == null || yaw.abs() < kSideYawMin) return null;
    return yaw > 0 ? 1 : -1;
  }

  Future<void> _captureCurrentStage(Face face) async {
    final cameraController = controller;
    if (cameraController == null || capturing) return;

    final stageBeforeCapture = _currentStage;
    final sideSign = _sideSignForYaw(face.headEulerAngleY);

    setState(() {
      capturing = true;
      _stableMatchCount = 0;
    });
    _setGuidance(
      'Capturing ${capturedPaths.length + 1} of 3',
      'Hold still while the photo is saved.',
    );

    try {
      await _stopImageStream();
      final photo = await cameraController.takePicture();
      if (!mounted) return;

      setState(() {
        capturedPaths.add(photo.path);
        if (stageBeforeCapture == _EnrollmentCaptureStage.firstSide) {
          _firstSideSign = sideSign;
        }
      });

      if (capturedPaths.length == 3) {
        Get.back(result: List<String>.from(capturedPaths));
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;

      _updateGuidanceForCurrentStage();
      await _startImageStream();
      if (!mounted) return;
      setState(() {
        capturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        capturing = false;
        error = 'Automatic capture failed: $e';
      });
    }
  }

  void _updateGuidanceForCurrentStage() {
    switch (_currentStage) {
      case _EnrollmentCaptureStage.front:
        _setGuidance(
          'Look straight ahead',
          'Face the camera directly. We will take the first photo automatically.',
        );
        break;
      case _EnrollmentCaptureStage.firstSide:
        _setGuidance(
          'Turn to one side',
          'Slowly turn your head to either side and keep your face inside the circle.',
        );
        break;
      case _EnrollmentCaptureStage.oppositeSide:
        _setGuidance(
          'Turn to the other side',
          'Move back through the center, then turn the other way for the final photo.',
        );
        break;
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

  // ML Kit expects platform-specific image metadata from the live camera stream.
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
        appBar: AppBar(title: const Text('Guided Face Scan')),
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
                      'Guided Face Scan',
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
                'Keep your face inside the circle. We will capture three photos automatically as you change angles.',
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
                  overlayOpacity: 0.24,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Container(
                          width: 292,
                          height: 292,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: capturing
                                  ? AppColors.success
                                  : Colors.white,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 18,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Captured ${capturedPaths.length} of 3',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(3, (index) {
                      final done = index < capturedPaths.length;
                      final active = index == capturedPaths.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: done
                              ? AppColors.primary.withValues(alpha: 0.16)
                              : active
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: done || active
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Center(
                          child: done
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: AppColors.primary,
                                )
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: active
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
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
                    'Good lighting and a single face in the frame will give the best enrollment result.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: capturing ? null : _restartScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Restart Scan'),
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
