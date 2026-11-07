import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/review_model.dart';

/// Token warna ulasan, mengikuti tema aplikasi
class RvC {
  static const star = Color(0xFFF59E0B); // amber, kontras cukup di atas putih untuk ikon
  static const starOff = Color(0xFFCBD5E1);
  static const ink = Color(0xFF0F172A);
  static const body = Color(0xFF334155);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const bg = Color(0xFFF8FAFC);
  static const brand = Color(0xFF0077E6);
}

TextStyle rvText(double size, {Color color = RvC.body, FontWeight weight = FontWeight.w500}) =>
    GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color);

const ratingWords = ['', 'Sangat buruk', 'Kurang', 'Cukup', 'Bagus', 'Sangat bagus'];

// ======================================================================
// BINTANG
// ======================================================================

/// Bintang tampilan (mendukung setengah bintang untuk rata-rata)
class StarDisplay extends StatelessWidget {
  final double value;
  final double size;
  const StarDisplay({super.key, required this.value, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rating ${formatRating(value)} dari 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final v = value - i;
          return Icon(
            v >= 0.75 ? Icons.star_rounded : (v >= 0.25 ? Icons.star_half_rounded : Icons.star_outline_rounded),
            size: size,
            color: v >= 0.25 ? RvC.star : RvC.starOff,
          );
        }),
      ),
    );
  }
}

/// Input bintang 1-5: bisa diketuk atau digeser. Tiap bintang punya area tap ≥ 48px.
class StarInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final double size;
  const StarInput({super.key, required this.value, required this.onChanged, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final cell = size < 40 ? 40.0 : size + 8;
    void fromDx(double dx) {
      final v = (dx / cell).ceil().clamp(1, 5);
      if (v != value) onChanged(v);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => fromDx(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => fromDx(d.localPosition.dx),
      child: Semantics(
        label: value == 0 ? 'Belum ada bintang' : '$value dari 5 bintang, ${ratingWords[value]}',
        slider: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final on = i < value;
            return SizedBox(
              width: cell,
              height: cell,
              child: AnimatedScale(
                scale: on ? 1 : 0.9,
                duration: const Duration(milliseconds: 120),
                child: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: size, color: on ? RvC.star : RvC.starOff),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ======================================================================
// RINGKASAN
// ======================================================================

/// Satu baris distribusi: "5 ▇▇▇▇▇▇ 12"
class RatingBar extends StatelessWidget {
  final int star;
  final int count;
  final int total;
  const RatingBar({super.key, required this.star, required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(width: 12, child: Text('$star', style: rvText(11, weight: FontWeight.w700))),
          const Icon(Icons.star_rounded, size: 11, color: RvC.star),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : count / total,
                minHeight: 7,
                backgroundColor: const Color(0xFFF1F5F9),
                color: RvC.star,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text('$count', textAlign: TextAlign.right, style: rvText(10.5, color: RvC.muted)),
          ),
        ],
      ),
    );
  }
}

class RatingSummaryCard extends StatelessWidget {
  final ReviewSummary summary;
  const RatingSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RvC.border),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(formatRating(s.average),
                  style: GoogleFonts.plusJakartaSans(fontSize: 34, fontWeight: FontWeight.w800, color: RvC.ink, height: 1)),
              const SizedBox(height: 4),
              StarDisplay(value: s.average),
              const SizedBox(height: 4),
              Text('${s.count} ulasan', style: rvText(11, color: RvC.muted)),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  RatingBar(star: star, count: s.distribution[star] ?? 0, total: s.count),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// KARTU ULASAN
// ======================================================================

class ReviewCard extends StatelessWidget {
  final ReviewModel review;

  /// Aksi tambahan di bawah kartu (mis. tombol balas / laporkan untuk mitra)
  final Widget? footer;
  final String? shopName;
  const ReviewCard({super.key, required this.review, this.footer, this.shopName});

  @override
  Widget build(BuildContext context) {
    final r = review;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RvC.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: r.isAnonymous ? const Color(0xFFE2E8F0) : const Color(0xFFE0F2FE),
                child: r.isAnonymous
                    ? const Icon(Icons.person_outline_rounded, size: 18, color: RvC.muted)
                    : Text(r.initial, style: rvText(13, color: RvC.brand, weight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.userName,
                        overflow: TextOverflow.ellipsis, style: rvText(13, color: RvC.ink, weight: FontWeight.w700)),
                    Text(
                      [r.timeAgo, if (r.wasEdited) 'diubah', if (r.serviceSummary.isNotEmpty) r.serviceSummary].join(' • '),
                      overflow: TextOverflow.ellipsis,
                      style: rvText(10.5, color: RvC.faint),
                    ),
                  ],
                ),
              ),
              StarDisplay(value: r.rating.toDouble(), size: 15),
            ],
          ),
          if (r.aspects.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final e in r.aspects.entries)
                  Text('${ReviewAspect.byKey(e.key)?.label ?? e.key} ${e.value}/5',
                      style: rvText(10.5, color: RvC.muted, weight: FontWeight.w600)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            r.comment.isNotEmpty ? r.comment : 'Memberi ${r.rating} bintang tanpa komentar.',
            style: rvText(12.5,
                color: r.comment.isNotEmpty ? RvC.body : RvC.faint, weight: FontWeight.w500)
                .copyWith(height: 1.45, fontStyle: r.comment.isNotEmpty ? FontStyle.normal : FontStyle.italic),
          ),
          if (r.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in r.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: RvC.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: RvC.border)),
                    child: Text(t, style: rvText(10.5, color: RvC.body, weight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
          if (r.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < r.photoUrls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => _PhotoViewer(urls: r.photoUrls, initial: i)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          r.photoUrls[i],
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 72,
                            height: 72,
                            color: RvC.bg,
                            child: const Icon(Icons.broken_image_outlined, color: RvC.faint),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (r.hasReply) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: RvC.bg, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.storefront_rounded, size: 14, color: RvC.brand),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Balasan ${shopName ?? 'outlet'}',
                            style: rvText(11.5, color: RvC.ink, weight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(r.reply!, style: rvText(12, color: RvC.body).copyWith(height: 1.4)),
                ],
              ),
            ),
          ],
          ?footer,
        ],
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final List<String> urls;
  final int initial;
  const _PhotoViewer({required this.urls, required this.initial});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
      body: PageView.builder(
        controller: PageController(initialPage: initial),
        itemCount: urls.length,
        itemBuilder: (_, i) => InteractiveViewer(maxScale: 5, child: Center(child: Image.network(urls[i]))),
      ),
    );
  }
}
