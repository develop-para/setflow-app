import 'package:flutter/material.dart';

import '../services/app_update_controller.dart';
import '../theme.dart';
import '../theme/icons.dart';

/// 홈에서는 새 버전이 있을 때만, 설정에서는 언제든 확인할 수 있다.
class AppUpdateTile extends StatefulWidget {
  const AppUpdateTile({this.onlyWhenAvailable = false, super.key});
  final bool onlyWhenAvailable;

  @override
  State<AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends State<AppUpdateTile> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppUpdates.instance.loadInstalledVersion();
    });
  }

  @override
  Widget build(BuildContext context) {
    final updates = AppUpdates.instance;
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        if (widget.onlyWhenAvailable &&
            (!updates.isAvailable || updates.release == null)) {
          return const SizedBox.shrink();
        }
        final release = updates.release;
        return ListTile(
          leading: const Icon(SetflowIcons.appUpdate),
          title: Text(
            widget.onlyWhenAvailable && release != null
                ? '새 버전 ${release.version}'
                : updates.isAvailable
                ? '앱 업데이트'
                : '앱 버전',
          ),
          subtitle: Text(
            '현재 버전 ${_installedVersionLabel(updates)}'
            '${release == null ? '' : '\n새 버전 ${release.version} (${release.build})'}',
          ),
          trailing: const Icon(SetflowIcons.forward),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const AppUpdateScreen()),
          ),
        );
      },
    );
  }
}

String _installedVersionLabel(AppUpdateController updates) =>
    updates.installedVersion?.label ??
    (updates.versionLoading ? '확인 중이에요' : '확인할 수 없어요');

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key});
  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdates.instance.loadInstalledVersion();
        AppUpdates.instance.check();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final updates = AppUpdates.instance;
    return Scaffold(
      appBar: AppBar(title: Text(updates.isAvailable ? '앱 업데이트' : '앱 버전')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: updates,
          builder: (context, _) {
            final release = updates.release;
            return ListView(
              padding: SetflowInsets.pageForm,
              children: [
                Text('현재 설치 버전', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  _installedVersionLabel(updates),
                  key: const ValueKey('installed-app-version'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (!updates.versionLoading && updates.installedVersion == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          updates.loadInstalledVersion(force: true),
                      child: const Text('버전 다시 확인'),
                    ),
                  ),
                const SizedBox(height: SetflowSpacing.md),
                if (!updates.isAvailable)
                  const Text('이 빌드는 앱 안에서 업데이트를 지원하지 않아요.'),
                if (updates.isAvailable) ...[
                  Text(
                    release == null
                        ? '새 버전을 확인해보세요'
                        : '새 버전 ${release.version} (${release.build})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  const Text(
                    '처음에는 초대받은 Google 계정을 연결해주세요. 연결한 뒤에는 새 버전을 자동으로 확인해 홈에서 알려드려요.',
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  if (release?.notes case final String notes
                      when notes.isNotEmpty) ...[
                    Text(notes),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                  if (updates.error case final String error) ...[
                    Text(
                      error,
                      style: TextStyle(color: context.setflowColors.error),
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                  ] else if (updates.checked &&
                      release == null &&
                      !updates.busy) ...[
                    const Text('현재 계정에 배포된 새 버전이 없어요.'),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                  if (updates.busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: SetflowSpacing.sm),
                    const Text('업데이트를 처리하고 있어요. 설치 안내가 나오면 진행해주세요.'),
                  ] else if (updates.isAvailable)
                    FilledButton(
                      onPressed: release == null
                          ? () => updates.check(interactive: true)
                          : updates.install,
                      child: Text(
                        release != null
                            ? '업데이트'
                            : updates.needsSignIn
                            ? '계정 연결하고 확인'
                            : '새 버전 확인',
                      ),
                    ),
                  if (release != null) ...[
                    const SizedBox(height: SetflowSpacing.sm),
                    const Text(
                      '운동 기록을 마친 뒤 진행해주세요. 다운로드 후 Android 설치 화면에서 확인하면 업데이트돼요.',
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
