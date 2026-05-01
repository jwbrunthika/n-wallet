import 'package:camera/camera.dart';

List<CameraDescription> gCameras = <CameraDescription>[];
String? gCameraLoadError;

Future<void> preloadCameras() async {
  try {
    gCameras = await availableCameras();
    gCameraLoadError = null;
  } catch (e) {
    gCameras = <CameraDescription>[];
    gCameraLoadError = '$e';
  }
}

Future<String?> ensureCamerasLoaded() async {
  if (gCameras.isNotEmpty) {
    return null;
  }

  try {
    gCameras = await availableCameras();
    gCameraLoadError = null;
  } catch (e) {
    gCameraLoadError = '$e';
    return 'Unable to load camera: $e';
  }

  if (gCameras.isEmpty) {
    return gCameraLoadError == null
        ? 'No camera found on this device.'
        : 'No camera found on this device. Last error: $gCameraLoadError';
  }

  return null;
}
