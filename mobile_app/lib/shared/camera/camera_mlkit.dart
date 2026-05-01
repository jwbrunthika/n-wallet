import 'package:flutter/services.dart' show DeviceOrientation;

const Map<DeviceOrientation, int> kCameraOrientations =
    <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

const double kFrontYawMax = 10;
const double kSideYawMin = 12;
