import 'dart:typed_data';

import 'package:image/image.dart';

Uint8List? resizeImage(Uint8List bytes) {
  // decodeImage will identify the format of the image and use the appropriate
  // decoder.
  final Image? image = decodeImage(bytes);

  if (image == null) {
    return null;
  }

  // Resize the image to a 120x? thumbnail (maintaining the aspect ratio).
  final Image returnImage = copyResize(image, width: 120);

  return returnImage.getBytes();
}
