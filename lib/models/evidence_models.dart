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

  static const Map<String, String> statusLabels = {
    'pending': 'Menunggu Verifikasi',
    'approved': 'Disetujui',
    'rejected': 'Ditolak',
    'appealed': 'Banding Ditinjau Washora',
    'appeal_approved': 'Banding Disetujui',
    'appeal_rejected': 'Banding Ditolak',
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
  });

  String get statusLabel => statusLabels[status] ?? status;
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved' || status == 'appeal_approved';
  bool get canAppeal => status == 'rejected';

  String get resolutionLabel {
    if (resolution == 'rewash') return 'Cuci ulang gratis';
    if (resolution == 'compensation') {
      final amount = (compensationAmount ?? 0).toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]}.',
          );
      return 'Ganti rugi Rp $amount';
    }
    return '-';
  }

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
    );
  }
}
