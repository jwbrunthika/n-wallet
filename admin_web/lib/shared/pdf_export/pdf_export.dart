import 'dart:typed_data';

import 'pdf_export_stub.dart'
    if (dart.library.html) 'pdf_export_web.dart'
    as pdf_export;

Future<void> exportPdfFile({
  required Uint8List bytes,
  required String filename,
}) {
  return pdf_export.exportPdfFile(bytes: bytes, filename: filename);
}
