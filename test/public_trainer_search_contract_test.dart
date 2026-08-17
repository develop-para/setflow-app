import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';

const _trainerId = '11111111-1111-4111-8111-111111111111';

void main() {
  group('public trainer search input contract', () {
    test('supports one Korean character and normalizes whitespace', () {
      expect(normalizePublicTrainerSearchQuery(' 김 '), '김');
      expect(normalizePublicTrainerSearchQuery('  근력\t  코치  '), '근력 코치');
      expect(normalizePublicTrainerSearchQuery('   '), isEmpty);
    });

    test('rejects oversized queries and unbounded page sizes', () {
      expect(
        () => normalizePublicTrainerSearchQuery('가' * 51),
        throwsArgumentError,
      );
      expect(validatePublicTrainerSearchPageSize(1), 1);
      expect(validatePublicTrainerSearchPageSize(30), 30);
      expect(() => validatePublicTrainerSearchPageSize(0), throwsArgumentError);
      expect(
        () => validatePublicTrainerSearchPageSize(31),
        throwsArgumentError,
      );
    });
  });

  test('AppState normalizes calls and caches results by exact UUID', () async {
    final repository = _SearchRepository();
    final state = AppState(businessRepository: repository);
    addTearDown(state.dispose);

    final page = await state.searchPublicTrainers(
      query: '  김   코치 ',
      cursor: 'opaque-cursor',
      pageSize: 7,
    );

    expect(repository.query, '김 코치');
    expect(repository.cursor, 'opaque-cursor');
    expect(repository.pageSize, 7);
    expect(page.items.single.profile.id, _trainerId);
    expect(state.publicTrainers.single.profile.id, _trainerId);
  });

  test('fallback ordering is exact, prefix, then contains', () async {
    final state = AppState(businessRepository: _LegacyRepository());
    addTearDown(state.dispose);
    state.publicTrainers = [
      _trainer('22222222-2222-4222-8222-222222222222', '박코치', keyword: '김'),
      _trainer('33333333-3333-4333-8333-333333333333', '김근력'),
      _trainer('44444444-4444-4444-8444-444444444444', '김'),
    ];

    final page = await state.searchPublicTrainers(query: '김');

    expect(page.items.map((item) => item.profile.displayName), [
      '김',
      '김근력',
      '박코치',
    ]);
    expect(page.nextCursor, isNull);
  });

  test('migration enforces safe ranked keyset server search', () {
    final sql = File(
      'supabase/migrations/20260816230638_searchable_public_trainer_directory.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains('security invoker'));
    expect(sql, isNot(contains('security definer')));
    expect(sql, contains("trainer.status = 'approved'"));
    expect(sql, contains('and trainer.is_public'));
    expect(sql, contains('(select auth.uid()) is null'));
    expect(sql, contains('char_length(v_query) > 50'));
    expect(sql, contains('page_size < 1 or page_size > 30'));
    expect(
      sql,
      contains('num_nonnulls(cursor_rank, cursor_rating, cursor_id)'),
    );
    expect(sql, contains('cursor_rank not between 0 and 2'));
    expect(
      sql,
      contains('when lower(trainer.display_name) = lower(v_query) then 0'),
    );
    expect(sql, contains("like lower(v_prefix_pattern) escape '\\' then 1"));
    expect(sql, contains('else 2'));
    expect(sql, contains('eligible.trainer_match_rank asc'));
    expect(sql, contains('eligible.trainer_rating_avg desc'));
    expect(sql, contains('eligible.trainer_id asc'));
    expect(sql, contains('limit (page_size + 1)'));
    expect(sql, contains('extensions.gin_trgm_ops'));
    expect(sql, contains('from public, anon, authenticated'));
    expect(sql, contains('to authenticated, service_role'));

    final projection = sql.substring(
      sql.indexOf('returns table ('),
      sql.indexOf('language plpgsql'),
    );
    expect(projection, isNot(contains('user_id')));
  });
}

PublicTrainer _trainer(String id, String name, {String? keyword}) =>
    PublicTrainer(
      profile: TrainerBusinessProfile(
        id: id,
        userId: '',
        displayName: name,
        status: BusinessProfileStatus.approved,
        isPublic: true,
        verified: true,
        rating: 4.8,
        postCount: 0,
        coachingTotal: 1,
        keyword: keyword,
      ),
      specialties: keyword == null ? const [] : [keyword],
    );

class _SearchRepository
    implements BusinessRepository, PublicTrainerSearchRepository {
  String? query;
  String? cursor;
  int? pageSize;

  @override
  Future<PublicTrainerSearchPage> searchPublicTrainers({
    String query = '',
    String? cursor,
    int pageSize = 20,
  }) async {
    this.query = query;
    this.cursor = cursor;
    this.pageSize = pageSize;
    return PublicTrainerSearchPage(items: [_trainer(_trainerId, '김코치')]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LegacyRepository implements BusinessRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
