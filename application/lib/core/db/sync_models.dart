/// Where a queued change stands.
enum OpState {
  /// Waiting to be sent (or to be sent again).
  pending,

  /// The server refused it. Kept so the owner can see it.
  rejected,

  /// Another device changed the record and the server kept its copy.
  conflict,
}

/// One queued change. Becomes an element of `p_operations` for `api_apply_operations`.
class OutboxOp {
  const OutboxOp({
    this.seq,
    required this.opId,
    required this.entity,
    required this.action,
    this.recordId,
    this.baseRev,
    required this.clientUpdatedAt,
    this.reason,
    this.payload = const {},
    this.state = OpState.pending,
    this.attempts = 0,
    this.errorCode,
    this.message,
  });

  /// Order of creation. Set by the store; it is the `seq` sent to the server.
  final int? seq;
  final String opId;
  final String entity;

  /// `upsert`, `delete` or `new_version`.
  final String action;
  final String? recordId;

  /// The `rev` of the record when it was last seen. Null for a create.
  final int? baseRev;
  final DateTime clientUpdatedAt;
  final String? reason;
  final Map<String, dynamic> payload;
  final OpState state;
  final int attempts;
  final String? errorCode;
  final String? message;

  OutboxOp copyWith({int? seq, int? baseRev, OpState? state, int? attempts, String? errorCode, String? message}) {
    return OutboxOp(
      seq: seq ?? this.seq,
      opId: opId,
      entity: entity,
      action: action,
      recordId: recordId,
      baseRev: baseRev ?? this.baseRev,
      clientUpdatedAt: clientUpdatedAt,
      reason: reason,
      payload: payload,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      errorCode: errorCode ?? this.errorCode,
      message: message ?? this.message,
    );
  }

  /// The operation as the server expects it (contract section 10).
  Map<String, dynamic> toWire() => {
        'op_id': opId,
        'seq': seq,
        'entity': entity,
        'action': action,
        if (recordId != null) 'record_id': recordId,
        if (baseRev != null) 'base_rev': baseRev,
        'client_updated_at': clientUpdatedAt.toUtc().toIso8601String(),
        if (reason != null) 'reason': reason,
        'payload': payload,
      };
}

/// The server's answer for one operation.
class OpResult {
  const OpResult({required this.opId, required this.result, this.rev, this.errorCode, this.message, this.originalResult});

  final String opId;

  /// `applied`, `duplicate`, `rejected` or `conflict`.
  final String result;
  final int? rev;
  final String? errorCode;
  final String? message;

  /// For a `duplicate` of an operation seen before: what happened the first time.
  final String? originalResult;

  factory OpResult.fromJson(Map<String, dynamic> json) {
    return OpResult(
      opId: json['op_id'] as String,
      result: json['result'] as String,
      rev: (json['rev'] as num?)?.toInt(),
      errorCode: json['error_code'] as String?,
      message: json['message'] as String?,
      originalResult: json['original_result'] as String?,
    );
  }

  /// What to treat the operation as. A `duplicate` means the server already handled it:
  /// a replay of an earlier operation, or a re-sent create. Unless the first time failed, that counts as applied.
  String get outcome {
    if (result != 'duplicate') return result;
    final first = originalResult;
    return (first == 'rejected' || first == 'conflict') ? first! : 'applied';
  }
}

/// One changed row from `api_pull_changes`.
class PulledRow {
  const PulledRow({required this.entity, required this.rev, required this.record});

  final String entity;
  final int rev;
  final Map<String, dynamic> record;

  factory PulledRow.fromJson(Map<String, dynamic> json) {
    return PulledRow(
      entity: json['entity'] as String,
      rev: (json['rev'] as num).toInt(),
      record: Map<String, dynamic>.from(json['record'] as Map),
    );
  }
}

class PullPage {
  const PullPage({required this.rows, required this.nextRev, required this.hasMore});

  final List<PulledRow> rows;
  final int nextRev;
  final bool hasMore;

  factory PullPage.fromJson(Map<String, dynamic> json) {
    return PullPage(
      rows: [for (final r in (json['rows'] as List? ?? const [])) PulledRow.fromJson(Map<String, dynamic>.from(r as Map))],
      nextRev: (json['next_rev'] as num?)?.toInt() ?? 0,
      hasMore: json['has_more'] == true,
    );
  }
}
