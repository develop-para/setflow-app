import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme/icons.dart';

/// Adds attribution that is not contained in the package's BSD code license.
/// Flutter already bundles dependency LICENSE files into [LicenseRegistry].
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['flutter_body_atlas anatomical artwork'],
      '''Human Anatomy Component System artwork by Ryan Graves.

Source:
https://www.figma.com/community/file/1320468164820924031/human-anatomy-component-system

Licensed under Creative Commons Attribution 4.0 International (CC BY 4.0):
https://creativecommons.org/licenses/by/4.0/

The flutter_body_atlas package modified the SVG structure and element IDs for stable muscle identifiers and interactive hit testing. Setflow recolors target-muscle paths and identifies secondary muscles in text; Setflow does not modify the packaged SVG files.''',
    );
  });
}

class OpenSourceLicensesTile extends StatelessWidget {
  const OpenSourceLicensesTile({super.key, this.tileKey});

  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      leading: const Icon(SetflowIcons.openSource),
      title: const Text('오픈소스 및 이미지 출처'),
      subtitle: const Text('운동 데이터와 근육 그림의 저작권·라이선스'),
      trailing: const Icon(SetflowIcons.forward),
      onTap: () => showLicensePage(
        context: context,
        applicationName: 'Setflow',
        applicationLegalese:
            '운동 데이터: free-exercise-db (Unlicense)\n'
            '인체 근육 그림: Ryan Graves (CC BY 4.0)',
      ),
    );
  }
}
