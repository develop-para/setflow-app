/// Small JSON cache port shared by read-only backend adapters.
///
/// The cache owns no Supabase types, so replacing the backend does not require
/// replacing the durable last-known-data format used during an outage.
abstract interface class BackendDocumentCache {
  Future<Map<String, dynamic>?> loadDocument(String key);

  Future<void> storeDocument(String key, Map<String, dynamic> document);
}

/// Exposes whether an adapter returned last-known data after a failed refresh.
abstract interface class CachedBackendReadStatus {
  bool get isUsingCachedData;

  Object? get lastReadError;
}
