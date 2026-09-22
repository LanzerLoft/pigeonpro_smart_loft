import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/drinker_preset.dart';

/// A 3D cylinder-shaped liquid wave tank widget for visualizing
/// real-time drinker flush (drain) and refill cycles.
class CylinderWaterTankWidget extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final int phase; // 0 = idle, 1 = drain, 2 = pause, 3 = fill
  final String phaseText;
  final int remainingSec;
  final int? currentMl;
  final int? targetMl;
  final double? currentLiters;
  final double? targetLiters;
  final double flowRateLpm;
  final String pumpName;
  final LastRefillRecord? lastRefill;
  final int? smartDrainSec;
  final double width;
  final double height;

  const CylinderWaterTankWidget({
    super.key,
    required this.progress,
    required this.phase,
    required this.phaseText,
    required this.remainingSec,
    this.currentMl,
    this.targetMl,
    this.currentLiters,
    this.targetLiters,
    this.flowRateLpm = 1.8,
    required this.pumpName,
    this.lastRefill,
    this.smartDrainSec,
    this.width = 220,
    this.height = 250,
  });

  @override
  State<CylinderWaterTankWidget> createState() =>
      _CylinderWaterTankWidgetState();
}

class _CylinderWaterTankWidgetState extends State<CylinderWaterTankWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine colors based on active phase
    final Color primaryWaveColor;
    final Color secondaryWaveColor;
    final Color glowColor;
    final String statusTitle;
    final IconData statusIcon;

    switch (widget.phase) {
      case 0: // Idle / Standby
        if (widget.currentMl == 0) {
          primaryWaveColor = const Color(0xFF475569); // Slate grey (dry)
          secondaryWaveColor = const Color(0xFF64748B);
          glowColor = const Color(0xFFEF4444); // Red/amber
          statusTitle = 'DRINKER BOWL DRY (0 mL)';
          statusIcon = Icons.warning_amber_rounded;
        } else if (widget.phaseText.isNotEmpty &&
            !widget.phaseText.startsWith('LAST REFILL') &&
            !widget.phaseText.startsWith('PRESET')) {
          primaryWaveColor = const Color(0xFF0284C7);
          secondaryWaveColor = const Color(0xFF38BDF8);
          glowColor = const Color(0xFF38BDF8);
          statusTitle = widget.phaseText;
          statusIcon = Icons.water_rounded;
        } else if (widget.lastRefill != null) {
          primaryWaveColor = const Color(0xFF0284C7); // Deep Sky Blue
          secondaryWaveColor = const Color(0xFF38BDF8); // Ice Cyan
          glowColor = const Color(0xFF38BDF8);
          statusTitle = 'LAST REFILL: ${widget.lastRefill!.timeAgo.toUpperCase()}';
          statusIcon = Icons.history_rounded;
        } else {
          primaryWaveColor = const Color(0xFF0284C7); // Deep Sky Blue
          secondaryWaveColor = const Color(0xFF38BDF8); // Ice Cyan
          glowColor = const Color(0xFF38BDF8);
          statusTitle = widget.phaseText.isNotEmpty ? widget.phaseText : 'STANDBY • READY';
          statusIcon = Icons.water_rounded;
        }
        break;
      case 1: // Drain
        primaryWaveColor = const Color(0xFFEF4444); // Crimson red
        secondaryWaveColor = const Color(0xFFF97316); // Amber orange
        glowColor = const Color(0xFFEF4444);
        statusTitle = widget.phaseText.isNotEmpty
            ? widget.phaseText
            : 'DRAINING OLD WATER';
        statusIcon = Icons.cleaning_services_rounded;
        break;
      case 2: // Settle Pause
        primaryWaveColor = const Color(0xFFF59E0B); // Amber
        secondaryWaveColor = const Color(0xFFD97706);
        glowColor = const Color(0xFFF59E0B);
        statusTitle = widget.phaseText.isNotEmpty
            ? widget.phaseText
            : 'SETTLE PAUSE DELAY';
        statusIcon = Icons.hourglass_top_rounded;
        break;
      case 4: // Completed
        primaryWaveColor = const Color(0xFF10B981); // Emerald green
        secondaryWaveColor = const Color(0xFF06B6D4); // Cyan
        glowColor = const Color(0xFF10B981);
        statusTitle = 'CYCLE COMPLETED';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 3: // Refill
      default:
        primaryWaveColor = const Color(0xFF10B981); // Emerald green
        secondaryWaveColor = const Color(0xFF0EA5E9).withValues(alpha: 0.85); // Ocean cyan
        glowColor = const Color(0xFF10B981);
        statusTitle = widget.phaseText.isNotEmpty
            ? widget.phaseText
            : 'REFILLING FRESH WATER';
        statusIcon = Icons.water_drop_rounded;
        break;
    }

    final double clampedProgress = widget.progress.clamp(0.0, 1.0);
    final int percentInt = (clampedProgress * 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main 3D Cylinder Vessel
        Center(
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.width / 2),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.22),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Custom Cylinder Glass Body & Wave Painter
                AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, child) {
                    return CustomPaint(
                      size: Size(widget.width, widget.height),
                      painter: _CylinderWavePainter(
                        animationValue: _waveController.value,
                        progress: clampedProgress,
                        primaryColor: primaryWaveColor,
                        secondaryColor: secondaryWaveColor,
                        glowColor: glowColor,
                        isDraining: widget.phase == 1 ||
                            widget.phaseText.contains('DRAIN'),
                      ),
                    );
                  },
                ),

                // 2. Center Metrics & Status Information (High Contrast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Status Badge Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        constraints: BoxConstraints(maxWidth: widget.width - 36),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: glowColor.withValues(alpha: 0.6),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, color: glowColor, size: 14),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                statusTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: glowColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Large Bold Percentage Display or Target Volume / Last Refilled / Current Level
                      Text(
                        (widget.phase == 0 ||
                                widget.phaseText.contains('MANUAL') ||
                                widget.phaseText.contains('EMPTY') ||
                                (widget.phase == 1 && widget.currentMl != null))
                            ? (widget.currentMl != null
                                ? '${widget.currentMl} mL'
                                : (widget.lastRefill != null
                                    ? '${widget.lastRefill!.volumeMl} mL'
                                    : (widget.targetMl != null
                                        ? '${widget.targetMl} mL'
                                        : '$percentInt%')))
                            : '$percentInt%',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: (widget.phase == 0 ||
                                  widget.phaseText.contains('MANUAL') ||
                                  widget.phaseText.contains('EMPTY') ||
                                  (widget.phase == 1 && widget.currentMl != null))
                              ? 32
                              : 38,
                          letterSpacing: -0.5,
                          height: 1.0,
                          shadows: const [
                            Shadow(
                              color: Colors.black87,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Live Volume readout if provided (mL / L)
                      if (widget.currentMl != null ||
                          widget.targetMl != null ||
                          (widget.phase == 0 && widget.lastRefill != null))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.phase == 1
                                ? (widget.currentMl != null
                                    ? '💧 Draining: ${widget.currentMl} mL in bowl'
                                    : (widget.phaseText.contains('MANUAL')
                                        ? '💧 Draining: ${widget.currentMl ?? 0} mL in bowl'
                                        : (widget.remainingSec > 0
                                            ? '${widget.remainingSec}s Drain Countdown'
                                            : '💧 Draining water...')))
                                : (widget.phase == 4
                                    ? '💧 ${widget.targetMl ?? widget.currentMl} mL Refilled'
                                    : (widget.phase == 0
                                        ? (widget.currentMl != null
                                            ? (widget.currentMl == 0
                                                ? '⚠️ Bowl Empty (0.00 L)'
                                                : '💧 Level: ${widget.currentMl} mL (~${((widget.currentLiters ?? (widget.currentMl! / 1000.0))).toStringAsFixed(2)} L)')
                                            : (widget.lastRefill != null
                                                ? '💧 Refilled ~${widget.lastRefill!.liters.toStringAsFixed(2)} L (${widget.lastRefill!.presetChipLabel})'
                                                : '💧 Target: ~${((widget.targetLiters ?? ((widget.targetMl ?? 1000) / 1000.0))).toStringAsFixed(2)} L'))
                                        : '💧 ${widget.currentMl} mL / ${widget.targetMl} mL')),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 6),

                      // Countdown / Seconds Left Badge or Ready Badge / Last Refill Timestamp
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: glowColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: glowColor.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          widget.phase == 4
                              ? '✓ Drinker Ready'
                              : (widget.phase == 0
                                  ? (widget.currentMl == 0
                                      ? '⚠️ Drinker Bowl Empty (0 mL)'
                                      : (widget.smartDrainSec != null &&
                                              widget.smartDrainSec! > 0
                                          ? '⚡ Smart Drain: ${widget.smartDrainSec}s (${widget.currentMl ?? widget.lastRefill?.volumeMl ?? 0}mL)'
                                          : (widget.lastRefill != null
                                              ? '✓ Cleaned @ ${widget.lastRefill!.shortTimeStr}'
                                              : '2-Stage Flush & Refill')))
                                  : (widget.phaseText.contains('MANUAL')
                                      ? '⚡ Manual Drain (${widget.remainingSec}s)'
                                      : (widget.remainingSec > 0
                                          ? '${widget.remainingSec}s remaining'
                                          : (widget.phaseText.isNotEmpty
                                              ? widget.phaseText
                                              : '⚡ Draining Actively')))),
                          style: TextStyle(
                            color: glowColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Bottom Info Row (Active Pump details and Flow Rate)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF334155),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Active Pump Tag / Last Refill Tag
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      widget.phase == 4
                          ? Icons.check_circle_rounded
                          : (widget.phase == 0
                              ? (widget.lastRefill != null
                                  ? Icons.history_edu_rounded
                                  : Icons.tune_rounded)
                              : Icons.bolt_rounded),
                      color: glowColor,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.currentMl == 0
                            ? 'Drinker Empty • Needs Refill'
                            : (widget.phase == 0 && widget.lastRefill != null
                                ? 'Last: ${widget.lastRefill!.presetName}'
                                : widget.pumpName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Flow Rate Tag
              Row(
                children: [
                  const Icon(Icons.speed_rounded,
                      color: Color(0xFF38BDF8), size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.flowRateLpm.toStringAsFixed(1)} L/min',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Custom painter that draws the 3D cylinder shape, glass reflections,
/// graduated measurement scale, and the dual sine-wave liquid.
class _CylinderWavePainter extends CustomPainter {
  final double animationValue; // 0.0 to 1.0
  final double progress; // 0.0 to 1.0
  final Color primaryColor;
  final Color secondaryColor;
  final Color glowColor;
  final bool isDraining;

  _CylinderWavePainter({
    required this.animationValue,
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.glowColor,
    required this.isDraining,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double rimHeight = math.min(22.0, h * 0.08);

    // Cylinder Path: rounded top and bottom caps with straight sides
    final Path cylinderPath = Path();
    cylinderPath.moveTo(0, rimHeight);
    // Left side down
    cylinderPath.lineTo(0, h - rimHeight);
    // Bottom curved base
    cylinderPath.arcToPoint(
      Offset(w, h - rimHeight),
      radius: Radius.elliptical(w / 2, rimHeight),
      clockwise: false,
    );
    // Right side up
    cylinderPath.lineTo(w, rimHeight);
    // Top curved rim
    cylinderPath.arcToPoint(
      Offset(0, rimHeight),
      radius: Radius.elliptical(w / 2, rimHeight),
      clockwise: true,
    );
    cylinderPath.close();

    // 1. Draw Cylinder Dark Glass Interior Background
    final Paint bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF0F172A).withValues(alpha: 0.95),
          const Color(0xFF1E293B).withValues(alpha: 0.85),
          const Color(0xFF0F172A).withValues(alpha: 0.95),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(cylinderPath, bgPaint);

    // 2. Draw Measurement Graduation Ticks on the Right Wall (Before water clipping)
    final Paint tickPaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.5)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const int totalTicks = 8;
    for (int i = 1; i < totalTicks; i++) {
      final double tickY = rimHeight + (h - 2 * rimHeight) * (i / totalTicks);
      final double tickLen = (i % 2 == 0) ? 14.0 : 8.0;
      canvas.drawLine(
        Offset(w - tickLen, tickY),
        Offset(w, tickY),
        tickPaint,
      );
    }

    // 3. Clip to Cylinder Path for the animated liquid waves
    canvas.save();
    canvas.clipPath(cylinderPath);

    final double usableHeight = h - 2 * rimHeight;
    final double clampedProgress = progress.clamp(0.0, 1.0);

    // Draw water liquid ONLY if progress is greater than threshold (truly dry when <= 0.005)
    if (clampedProgress > 0.005) {
      final double waterLevelY =
          (h - rimHeight) - (usableHeight * clampedProgress);

      // Wave amplitude flattens out smoothly as water level approaches zero
      final double waveAmplitude = math.min(10.0, clampedProgress * 8.0);
      final double waveFrequency = 2 * math.pi / w;

      // Whirlpool vortex surface depression when draining
      double vortexOffset(double x) {
        if (!isDraining) return 0.0;
        final double distFromCenter = (x - w / 2).abs();
        final double radius = w * 0.38;
        if (distFromCenter >= radius) return 0.0;
        final double norm = 1.0 - (distFromCenter / radius);
        return (norm * norm) *
            math.min(10.0, usableHeight * clampedProgress * 0.4);
      }

      // --- Back Wave (Secondary wave, phase shifted) ---
      final Path backWavePath = Path();
      backWavePath.moveTo(0, h);
      for (double x = 0; x <= w; x += 3) {
        final double vOffset = vortexOffset(x);
        final double y = waterLevelY +
            vOffset +
            (waveAmplitude * 0.75) *
                math.sin(waveFrequency * x +
                    (animationValue * 2 * math.pi) +
                    math.pi / 2);
        backWavePath.lineTo(x, y);
      }
      backWavePath.lineTo(w, h);
      backWavePath.close();

      final Paint backWavePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            secondaryColor.withValues(alpha: 0.45),
            primaryColor.withValues(alpha: 0.25),
          ],
        ).createShader(Rect.fromLTWH(0, waterLevelY - waveAmplitude, w, h));

      canvas.drawPath(backWavePath, backWavePaint);

      // --- Front Wave (Vibrant foreground wave) ---
      final Path frontWavePath = Path();
      frontWavePath.moveTo(0, h);
      for (double x = 0; x <= w; x += 3) {
        final double vOffset = vortexOffset(x);
        final double y = waterLevelY +
            vOffset +
            waveAmplitude *
                math.sin(waveFrequency * x - (animationValue * 2 * math.pi));
        frontWavePath.lineTo(x, y);
      }
      frontWavePath.lineTo(w, h);
      frontWavePath.close();

      final Paint frontWavePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            secondaryColor.withValues(alpha: 0.85),
            primaryColor.withValues(alpha: 0.95),
          ],
        ).createShader(Rect.fromLTWH(0, waterLevelY - waveAmplitude, w, h));

      canvas.drawPath(frontWavePath, frontWavePaint);

      // --- Draining Visual Effects ---
      if (isDraining) {
        // 1. Vortex Suction Swirl Rings on surface
        final double vortexY = waterLevelY + vortexOffset(w / 2);
        final Paint vortexRingPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFFF97316).withValues(alpha: 0.7);

        final double swirlScale = ((animationValue * 2) % 1.0);
        final double vortexWidth = (w * 0.28) * (1.0 - swirlScale * 0.4);
        final double vortexHeight = math.min(10.0, vortexWidth * 0.3);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(w / 2, vortexY),
            width: vortexWidth,
            height: vortexHeight,
          ),
          vortexRingPaint,
        );

        // 2. Downward Suction Particles / Drain Bubbles (pulled down into bottom port)
        final Paint drainParticlePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.75)
          ..style = PaintingStyle.fill;

        for (int i = 0; i < 7; i++) {
          final double cycle = (animationValue + (i * 0.15)) % 1.0;
          // Particles move downward towards bottom drain
          final double particleY =
              vortexY + ((h - rimHeight - vortexY) * cycle);
          // Converge towards horizontal center as they near bottom
          final double startOffset = ((i - 3) * (w * 0.08));
          final double particleX = (w / 2) + (startOffset * (1.0 - cycle));

          if (particleY > vortexY && particleY < (h - rimHeight)) {
            canvas.drawCircle(
              Offset(particleX, particleY),
              1.5 + (i % 2),
              drainParticlePaint,
            );
          }
        }

        // 3. Bottom Drain Port Suction Funnel
        final Path drainOutflowPath = Path();
        final double drainBaseY = h - rimHeight;
        drainOutflowPath.moveTo(w * 0.42, drainBaseY - 14);
        drainOutflowPath.lineTo(w * 0.58, drainBaseY - 14);
        drainOutflowPath.lineTo(w * 0.52, drainBaseY + 4);
        drainOutflowPath.lineTo(w * 0.48, drainBaseY + 4);
        drainOutflowPath.close();

        final Paint drainFlowPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFEF4444).withValues(alpha: 0.6),
              const Color(0xFFF97316).withValues(alpha: 0.2),
            ],
          ).createShader(Rect.fromLTWH(w * 0.4, drainBaseY - 14, w * 0.2, 20));

        canvas.drawPath(drainOutflowPath, drainFlowPaint);
      } else {
        // Normal state: Rising micro-bubbles
        final Paint bubblePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill;

        for (int i = 0; i < 5; i++) {
          final double bubbleX = (w * 0.2) + ((i * 37) % (w * 0.6));
          final double bubbleCycle = (animationValue + (i * 0.2)) % 1.0;
          final double bubbleY =
              (h - rimHeight) - (usableHeight * clampedProgress * bubbleCycle);
          if (bubbleY > waterLevelY) {
            canvas.drawCircle(
              Offset(bubbleX, bubbleY),
              2.0 + (i % 2),
              bubblePaint,
            );
          }
        }
      }
    } else {
      // DRY / EMPTY TANK VISUALS
      // Draw subtle dry floor plate with glowing base ring
      final Rect basePlateRect = Rect.fromCenter(
        center: Offset(w / 2, h - rimHeight),
        width: w * 0.85,
        height: rimHeight * 1.4,
      );
      final Paint dryFloorPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(alpha: 0.15),
            Colors.transparent,
          ],
        ).createShader(basePlateRect);
      canvas.drawOval(basePlateRect, dryFloorPaint);

      // Empty bowl center drain port indicator
      final Paint drainPortPaint = Paint()
        ..color = const Color(0xFF475569).withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(w / 2, h - rimHeight), 8.0, drainPortPaint);
    }

    // 4. Glass Reflection Highlight (Curved vertical gloss on the left)
    final Path glossPath = Path();
    glossPath.moveTo(w * 0.12, rimHeight + 6);
    glossPath.lineTo(w * 0.12, h - rimHeight - 6);
    glossPath.lineTo(w * 0.18, h - rimHeight - 6);
    glossPath.lineTo(w * 0.18, rimHeight + 6);
    glossPath.close();

    final Paint glossPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0.15),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(glossPath, glossPaint);

    canvas.restore(); // Restore from clipping

    // 5. Outer Cylinder Glass Border & Glowing Rim
    final Paint borderPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawPath(cylinderPath, borderPaint);

    // 6. Top Opening Rim Ellipse (Gives 3D depth to top cap)
    final Rect topRimRect = Rect.fromCenter(
      center: Offset(w / 2, rimHeight),
      width: w,
      height: rimHeight * 2,
    );

    final Paint topRimPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawOval(topRimRect, topRimPaint);
  }

  @override
  bool shouldRepaint(covariant _CylinderWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.isDraining != isDraining;
  }
}
