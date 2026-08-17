import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/welcome_screen.dart';
import 'package:setflow/services/post_media_picker.dart';
import 'package:setflow/services/trainer_document_picker.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

const _userId = '11111111-1111-4111-8111-111111111111';

void main() {
  test('picker reads XFile bytes without dart:io platform paths', () async {
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
      'A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final gateway = _ImageGateway(
      XFile.fromData(pngBytes, name: 'license.png', mimeType: 'image/png'),
    );
    final picker = ImagePickerTrainerDocumentPicker(gateway: gateway);

    final picked = await picker.pick(TrainerDocumentSource.camera);

    expect(picked?.bytes, orderedEquals(pngBytes));
    expect(picked?.contentType, 'image/png');
    expect(gateway.lastSource, ImageSource.camera);
  });

  testWidgets('live trainer onboarding requires two actual picker results', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final picker = _DocumentPicker([
      _picked('certificate.jpg'),
      _picked('identity.jpg'),
    ]);
    final state = AppState(businessRepository: _ApplicationRepository());
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: BusinessSetupScreen(
            role: UserRole.trainer,
            trainerDocumentPicker: picker,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '실트레이너');
    await tester.enterText(fields.at(1), 'CERT-1234');
    await tester.pump();
    await tester.ensureVisible(find.text('다음 · 서류 제출'));
    await tester.tap(find.text('다음 · 서류 제출'));
    await tester.pumpAndSettle();

    expect(find.text('인증 서류를\n제출해주세요'), findsOneWidget);
    expect(find.textContaining('실제 파일 업로드 없이'), findsNothing);
    expect(_submissionButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('trainer-document-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trainer-document-gallery')));
    await tester.pumpAndSettle();
    expect(find.text('certificate.jpg'), findsOneWidget);
    expect(_submissionButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('trainer-document-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trainer-document-camera')));
    await tester.pumpAndSettle();
    expect(find.text('identity.jpg'), findsOneWidget);
    expect(_submissionButton(tester).onPressed, isNotNull);
    expect(picker.sources, [
      TrainerDocumentSource.gallery,
      TrainerDocumentSource.camera,
    ]);
  });

  test('AppState forwards typed documents to the live repository', () async {
    final repository = _ApplicationRepository();
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    final documents = [
      _input(
        TrainerApplicationDocumentType.nationalCertificate,
        'certificate.jpg',
      ),
      _input(TrainerApplicationDocumentType.identity, 'identity.jpg'),
    ];

    await state.submitTrainerBusinessApplication(
      displayName: '실트레이너',
      credentialNumber: 'CERT-1234',
      documents: documents,
    );

    expect(repository.inputs, hasLength(1));
    expect(repository.inputs.single.documents, same(documents));
    expect(repository.inputs.single.documents.map((item) => item.type), [
      TrainerApplicationDocumentType.nationalCertificate,
      TrainerApplicationDocumentType.identity,
    ]);
  });

  test(
    'migration requires owned Storage objects and blocks old RPC bypass',
    () {
      final sql = File(
        'supabase/migrations/'
        '20260816032841_trainer_application_document_upload.sql',
      ).readAsStringSync();

      expect(sql, contains("o.bucket_id = 'trainer-documents'"));
      expect(sql, contains('o.owner = v_user_id'));
      expect(sql, contains('file_size_limit'));
      expect(sql, contains('trainer_document_storage_policy_preflight'));
      expect(sql, contains("p.polname = 'priv_write'"));
      expect(sql, contains("p.polname = 'priv_read'"));
      expect(sql, contains("p.polname = 'priv_delete'"));
      expect(sql, isNot(contains('storage_trainer_documents_owner_')));
      expect(
        sql,
        contains("'Identity and certification documents are required'"),
      );
      expect(
        sql,
        contains(
          "select private.submit_trainer_application(\$1, \$2, '[]'::jsonb)",
        ),
      );
      expect(sql, contains('revoke insert, update, delete'));
    },
  );
}

AppButton _submissionButton(WidgetTester tester) => tester
    .widgetList<AppButton>(find.byType(AppButton))
    .singleWhere((button) => button.label == '서류 제출하기');

PickedTrainerDocument _picked(String name) => PickedTrainerDocument(
  bytes: Uint8List.fromList([1, 2, 3]),
  fileName: name,
  contentType: 'image/jpeg',
);

TrainerApplicationDocumentInput _input(
  TrainerApplicationDocumentType type,
  String name,
) => TrainerApplicationDocumentInput(
  type: type,
  bytes: Uint8List.fromList([1, 2, 3]),
  fileName: name,
  contentType: 'image/jpeg',
);

class _DocumentPicker implements TrainerDocumentPicker {
  _DocumentPicker(this.documents);

  final List<PickedTrainerDocument> documents;
  final List<TrainerDocumentSource> sources = [];
  int index = 0;

  @override
  Future<PickedTrainerDocument?> pick(TrainerDocumentSource source) async {
    sources.add(source);
    return documents[index++];
  }
}

class _ImageGateway implements ImagePickerGateway {
  _ImageGateway(this.file);

  final XFile file;
  ImageSource? lastSource;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    required double maxWidth,
    required double maxHeight,
    required int imageQuality,
    required bool requestFullMetadata,
  }) async {
    lastSource = source;
    return file;
  }

  @override
  Future<LostDataResponse> retrieveLostData() => throw UnimplementedError();
}

class _ApplicationRepository implements BusinessRepository {
  final List<TrainerApplicationInput> inputs = [];

  @override
  Future<BusinessApplication> submitTrainerApplication(
    TrainerApplicationInput input,
  ) async {
    inputs.add(input);
    return const BusinessApplication(
      id: '22222222-2222-4222-8222-222222222222',
      kind: BusinessApplicationKind.trainer,
      status: BusinessApplicationStatus.pending,
      applicantName: '실트레이너',
    );
  }

  @override
  Future<BusinessAccess> loadAccess() async => const BusinessAccess(
    userId: _userId,
    accountRole: UserRole.member,
    resolvedRole: UserRole.member,
    availableRoles: {UserRole.member},
  );

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => const [];

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async => const [];

  @override
  Future<MemberSharingPreferences> loadMySharingPreferences() async =>
      const MemberSharingPreferences(
        shareBodyData: false,
        shareWorkoutRecords: false,
        marketing: false,
      );

  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => const [];

  @override
  Future<List<RoutineShareRecord>> listIncomingRoutineShares() async =>
      const [];

  @override
  Future<List<PersonalRoutineRecord>> listPersonalRoutines() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
