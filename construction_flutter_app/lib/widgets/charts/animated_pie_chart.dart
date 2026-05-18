import 'dart:math';
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';

class AnimatedPieChart extends StatefulWidget {
  final Map<String, double> dataValues;
  final Map<String, Color>? colors;

  const AnimatedPieChart({super.key, required this.dataValues, this.colors});

  @override
  State<AnimatedPieChart> createState() => _AnimatedPieChartState();
}

class _AnimatedPieChartState extends State<AnimatedPieChart> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    // Start entrance animation immediately
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedPieChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataValues != widget.dataValues) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Strictly order materials to ensure consistent color mapping
    final List<String> strictOrder = ['cement', 'bricks', 'steel', 'sand', 'aggregate'];
    
    final Map<String, double> orderedValues = {};
    for (final mat in strictOrder) {
      if (widget.dataValues.containsKey(mat)) {
        orderedValues[mat] = widget.dataValues[mat]!;
      } else {
        // Fallback for case-insensitive match
        final match = widget.dataValues.keys.firstWhere(
          (k) => k.toLowerCase() == mat,
          orElse: () => '',
        );
        if (match.isNotEmpty) {
          orderedValues[mat] = widget.dataValues[match]!;
        }
      }
    }

    // Include any other categories not in the strict list at the end
    widget.dataValues.forEach((key, val) {
      final lowerKey = key.toLowerCase();
      if (!strictOrder.contains(lowerKey)) {
        orderedValues[lowerKey] = val;
      }
    });

    final total = orderedValues.values.fold(0.0, (sum, val) => sum + val);

    return Container(
      width: double.infinity,
      height: 320,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return CustomPaint(
            painter: _PieChartPainter(
              data: orderedValues,
              total: total,
              progress: _animation.value,
            ),
          );
        },
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final Map<String, double> data;
  final double total;
  final double progress;

  _PieChartPainter({
    required this.data,
    required this.total,
    required this.progress,
  });

  // Strict color sequence forced across all projects:
  // 1. Red, 2. Green, 3. Dark Blue, 4. Violet, 5. Orange
  final List<Color> _strictColors = [
    const Color(0xFFE53935), // Red
    const Color(0xFF43A047), // Green
    const Color(0xFF1E3A8A), // Dark Blue
    const Color(0xFF8E24AA), // Violet (Purple)
    const Color(0xFFFB8C00), // Orange
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final chartRadius = min(size.width, size.height) / 4.2;

    if (total == 0 || data.isEmpty) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'No Data Available',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
      return;
    }

    final rect = Rect.fromCircle(center: center, radius: chartRadius);

    // --- PHASE 1: Loading ring (0.0 to 0.3) ---
    final double ringProgress = (progress / 0.3).clamp(0.0, 1.0);
    final ringPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawCircle(center, chartRadius, ringPaint);
    
    if (progress < 0.3) {
      final activeRingPaint = Paint()
        ..color = DFColors.primaryStitch.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -pi / 2, 2 * pi * ringProgress, false, activeRingPaint);
      return;
    }

    // --- PHASE 2: Fill Colored Slices (0.3 to 0.7) ---
    final double fillProgress = ((progress - 0.3) / 0.4).clamp(0.0, 1.0);
    final double maxStrokeWidth = chartRadius * 0.45;
    final double currentStrokeWidth = maxStrokeWidth * fillProgress;

    double startAngle = -pi / 2;
    int colorIndex = 0;

    final List<MapEntry<String, double>> entries = data.entries.toList();
    final List<_SliceLayout> slices = [];

    for (final entry in entries) {
      final sweepAngle = (entry.value / total) * 2 * pi;
      final color = _strictColors[colorIndex % _strictColors.length];
      colorIndex++;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = currentStrokeWidth;

      // Draw active slice adjusting radius to center-align the stroke
      final sliceRect = Rect.fromCircle(center: center, radius: chartRadius - currentStrokeWidth / 2);
      
      // The slice sweeps in based on the current fillProgress
      final currentSweep = sweepAngle * fillProgress;
      canvas.drawArc(sliceRect, startAngle, currentSweep, false, paint);

      // Save slice details for drawing callout lines in Phase 3
      slices.add(_SliceLayout(
        name: entry.key,
        value: entry.value,
        startAngle: startAngle,
        sweepAngle: currentSweep,
        color: color,
      ));

      startAngle += sweepAngle;
    }

    // --- PHASE 3: Bent Callout Lines & Labels (0.6 to 1.0) ---
    if (progress < 0.6) return;
    final double lineProgress = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);

    for (final slice in slices) {
      final midAngle = slice.startAngle + slice.sweepAngle / 2;
      final cosVal = cos(midAngle);
      final sinVal = sin(midAngle);

      // Starting point on the slice's outer boundary
      final pStart = center + Offset(cosVal, sinVal) * chartRadius;

      // First bend point (extend outwards radially)
      final pMid = pStart + Offset(cosVal, sinVal) * (22 * lineProgress);

      // Second horizontal bend point (left/right split)
      final bool isRight = cosVal >= 0;
      final pEnd = pMid + Offset(isRight ? 28 * lineProgress : -28 * lineProgress, 0);

      // Draw the bent line
      final linePaint = Paint()
        ..color = slice.color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final path = Path()
        ..moveTo(pStart.dx, pStart.dy)
        ..lineTo(pMid.dx, pMid.dy)
        ..lineTo(pEnd.dx, pEnd.dy);
      canvas.drawPath(path, linePaint);

      // Draw small elegant joint dot at the start of callout
      final dotPaint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pStart, 3, dotPaint);

      // Render outer text labels adjacent to the line end
      final displayName = slice.name.length > 1
          ? '${slice.name[0].toUpperCase()}${slice.name.substring(1)}'
          : slice.name;

      final formattedVal = slice.value >= 1000
          ? '₹${(slice.value / 1000).toStringAsFixed(1)}k'
          : '₹${slice.value.toStringAsFixed(0)}';

      final textSpan = TextSpan(
        children: [
          TextSpan(
            text: '$displayName\n',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              height: 1.2,
              fontFamily: 'Inter',
            ),
          ),
          TextSpan(
            text: formattedVal,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
              fontSize: 10,
              fontFamily: 'Inter',
            ),
          ),
        ],
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      // Adjust text position slightly offset from the end of the line
      double textX = pEnd.dx;
      if (isRight) {
        textX += 6;
      } else {
        textX -= (textPainter.width + 6);
      }
      final textY = pEnd.dy - textPainter.height / 2;

      // Draw text with fading opacity
      canvas.save();
      final opacityPaint = Paint()..color = Colors.white.withValues(alpha: lineProgress);
      canvas.saveLayer(Rect.fromLTWH(textX, textY, textPainter.width, textPainter.height), opacityPaint);
      textPainter.paint(canvas, Offset(textX, textY));
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.total != total ||
        oldDelegate.data != data;
  }
}

class _SliceLayout {
  final String name;
  final double value;
  final double startAngle;
  final double sweepAngle;
  final Color color;

  _SliceLayout({
    required this.name,
    required this.value,
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
  });
}
