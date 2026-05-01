import 'dart:io';

import 'package:camera_android/camera_android.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mobile_app/app/student_app.dart';
import 'package:mobile_app/features/auth/controllers/student_auth_controller.dart';
import 'package:mobile_app/features/beacon/controllers/beacon_scan_controller.dart';
import 'package:mobile_app/features/student/controllers/student_data_controller.dart';
import 'package:mobile_app/shared/camera/camera_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  if (Platform.isAndroid) {
    AndroidCamera.registerWith();
  }
  await GetStorage.init();
  await preloadCameras();

  Get.put(StudentAuthController());
  Get.put(BeaconScanController());
  Get.put(StudentDataController());

  runApp(const StudentApp());
}
