/// Foto bukti pesanan: penerimaan (intake), serah terima (handover), atau klaim (claim)
class OrderPhoto {
  final String id;
  final String orderId;
  final String stage; // 'intake' | 'handover' | 'claim'
  final String storagePath;
  final DateTime createdAt;
  final String? url; // signed URL sementara untuk ditampilkan

  OrderPhoto({
    required this.id,
    required this.orderId,
    required this.stage,
    required this.storagePath,
    required this.createdAt,
    this.url,
  });

  factory OrderPhoto.fromMap(Map<String, dynamic> data, {String? url}) {
    return OrderPhoto(
      id: data['id'] ?? '',
      orderId: data['order_id'] ?? '',
      stage: data['stage'] ?? '',
      storagePath: data['storage_path'] ?? '',
      createdAt: data['created_at'] != null
          ? DateTime.parse(data['created_at']).toLocal()
          : DateTime.now(),
      url: url,
    );
  }
}

/// Klaim kerusakan dari pelanggan
class DamageClaim {
  final String id;
  final String orderId;
  final String userId;
  final String shopId;
  final String description;
  final String status; // pending | approved | rejected | appealed | appeal_approved | appeal_rejected
  final String? resolution; // rewash | compensation
  final int? compensationAmount;
  final String? ownerNote;
  final String? appealReason;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? decidedAt;

  // Lanjutan (supabase_klaim_lanjutan.sql)
  final String? category; // torn | faded | stain | shrunk | missing | accessory | smell | other
  final List<String> affectedItems; // nama item pesanan yang terdampak
  final String? requestedResolution; // rewash | compensation | points
  final int? requestedAmount;
  final DateTime? appealedAt;
  final DateTime? resolvedAt;
  final String? resolvedNote;
  final bool escalated;

  /// Batas respons outlet
  static const Duration responseWindow = Duration(hours: 48);

  static const Map<String, String> categoryLabels = {
    'torn': 'Robek / berlubang',
    'faded': 'Luntur / berubah warna',
    'stain': 'Noda baru',
    'shrunk': 'Menyusut / melar',
    'missing': 'Item hilang',
    'accessory': 'Kancing / resleting rusak',
    'smell': 'Bau tidak sedap',
    'other': 'Lainnya',
  };

  static const Map<String, String> statusLabels = {
    'pending': 'Menunggu Verifikasi',
    'approved': 'Disetujui',
    'rejected': 'Ditolak',
    'appealed': 'Banding Ditinjau Washora',
    'appeal_approved': 'Banding Disetujui',
    'appeal_rejected': 'Banding Ditolak',
    'resolved': 'Selesai',
  };

  DamageClaim({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.shopId,
    required this.description,
    required this.status,
    this.resolution,
    this.compensationAmount,
    this.ownerNote,
    this.appealReason,
    this.adminNote,
    required this.createdAt,
    this.decidedAt,
    this.category,
    this.affectedItems = const [],
    this.requestedResolution,
    this.requestedAmount,
    this.appealedAt,
    this.resolvedAt,
    this.resolvedNote,
    this.escalated = false,
  });

  String? get categoryLabel => category == null ? null : categoryLabels[category] ?? category;
  bool get isResolved => status == 'resolved';
  DateTime get responseDeadline => createdAt.add(responseWindow);
  bool get isOverdue => isPending && DateTime.now().isAfter(responseDeadline);
  bool get canEscalate => isOverdue;

  /// Disetujui tapi belum dituntaskan outlet (cuci ulang / transfer ganti rugi)
  bool get awaitingSettlement => isApproved && resolution != 'points';

  static String _rp(int v) =>
      'Rp ${v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  static String resolutionText(String? r, int? amount) => switch (r) {
        'rewash' => 'Cuci ulang gratis',
        'compensation' => amount == null ? 'Ganti rugi uang' : 'Ganti rugi ${_rp(amount)}',
        'points' => amount == null ? 'Poin Washora' : '$amount poin (= ${_rp(amount)})',
        _ => '-',
      };

  String get requestedLabel => resolutionText(requestedResolution, requestedAmount);

  String get statusLabel => statusLabels[status] ?? status;
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved' || status == 'appeal_approved';
  bool get canAppeal => status == 'rejected';

  String get resolutionLabel => resolutionText(resolution, compensationAmount);

  factory DamageClaim.fromMap(Map<String, dynamic> data) {
    return DamageClaim(
      id: data['id'] ?? '',
      orderId: data['order_id'] ?? '',
      userId: data['user_id'] ?? '',
      shopId: data['shop_id'] ?? '',
      description: data['description'] ?? '',
      status: data['status'] ?? 'pending',
      resolution: data['resolution'],
      compensationAmount: data['compensation_amount'],
      ownerNote: data['owner_note'],
      appealReason: data['appeal_reason'],
      adminNote: data['admin_note'],
      createdAt: data['created_at'] != null
          ? DateTime.parse(data['created_at']).toLocal()
          : DateTime.now(),
      decidedAt: data['decided_at'] != null ? DateTime.parse(data['decided_at']).toLocal() : null,
      category: data['category'],
      affectedItems: (data['affected_items'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      requestedResolution: data['requested_resolution'],
      requestedAmount: (data['requested_amount'] as num?)?.toInt(),
      appealedAt: data['appealed_at'] != null ? DateTime.parse(data['appealed_at']).toLocal() : null,
      resolvedAt: data['resolved_at'] != null ? DateTime.parse(data['resolved_at']).toLocal() : null,
      resolvedNote: data['resolved_note'],
      escalated: data['escalated'] == true,
    );
  }
}

/// Statistik klaim outlet (RPC claim_stats)
class ClaimStats {
  final int total;
  final int pending;
  final int overdue;
  final int resolved;
  final int? approvedRate; // % klaim yang diberi penyelesaian
  final double? avgResponseHours;
  final double? claimRatePct; // klaim per 100 pesanan selesai

  const ClaimStats({
    required this.total,
    required this.pending,
    required this.overdue,
    required this.resolved,
    this.approvedRate,
    this.avgResponseHours,
    this.claimRatePct,
  });

  factory ClaimStats.fromJson(Map<String, dynamic> j) => ClaimStats(
        total: (j['total'] as num?)?.toInt() ?? 0,
        pending: (j['pending'] as num?)?.toInt() ?? 0,
        overdue: (j['overdue'] as num?)?.toInt() ?? 0,
        resolved: (j['resolved'] as num?)?.toInt() ?? 0,
        approvedRate: (j['approved_rate'] as num?)?.toInt(),
        avgResponseHours: (j['avg_response_hours'] as num?)?.toDouble(),
        claimRatePct: (j['claim_rate_pct'] as num?)?.toDouble(),
      );
}
