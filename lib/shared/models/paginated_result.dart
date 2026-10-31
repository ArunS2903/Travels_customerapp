/// One page of a list endpoint, matching the backend's pagination envelope.
class PaginatedResult<T> {
  const PaginatedResult({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<T> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;

  factory PaginatedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemParser,
  ) {
    final rawItems = json['items'];
    final page = (json['page'] as num?)?.toInt() ?? 1;
    final limit = (json['limit'] as num?)?.toInt() ?? 10;
    final total = (json['total'] as num?)?.toInt() ?? 0;

    return PaginatedResult<T>(
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => itemParser(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      page: page,
      limit: limit,
      total: total,
      // Prefer the server's answer; fall back to arithmetic if it is absent.
      hasMore: (json['hasMore'] as bool?) ?? page * limit < total,
    );
  }

  static PaginatedResult<T> empty<T>() =>
      PaginatedResult<T>(items: const [], page: 1, limit: 10, total: 0, hasMore: false);

  /// Appends the next page onto an accumulated list.
  PaginatedResult<T> merge(PaginatedResult<T> next) => PaginatedResult<T>(
        items: [...items, ...next.items],
        page: next.page,
        limit: next.limit,
        total: next.total,
        hasMore: next.hasMore,
      );

  bool get isEmpty => items.isEmpty;
}
