import 'dart:convert';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../data/local_equipment_repository.dart';

abstract interface class EquipmentBackupFiles {
  Future<void> export(String source, Rect origin);
  Future<String?> import();
}

class PlatformEquipmentBackupFiles implements EquipmentBackupFiles {
  @override
  Future<void> export(String source, Rect origin) async {
    final name =
        'setflow-equipment-${DateTime.now().millisecondsSinceEpoch}.json';
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(source)),
      name: name,
      mimeType: 'application/json',
    );
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await Share.shareXFiles(
        [file],
        fileNameOverrides: [name],
        sharePositionOrigin: origin,
      );
    } else if (kIsWeb) {
      await file.saveTo(name);
    } else {
      final location = await getSaveLocation(suggestedName: name);
      if (location != null) await file.saveTo(location.path);
    }
  }

  @override
  Future<String?> import() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '셋플로우 기구 백업',
          extensions: ['json'],
          mimeTypes: ['application/json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > EquipmentBackupCodec.maxBytes) {
      throw const FormatException('백업 파일은 64MB 이하여야 해요.');
    }
    return utf8.decode(await file.readAsBytes());
  }
}
