// lib/views/widgets/wifi_marker_widget.dart
//Маркер Wi-Fi точки
import 'package:flutter/material.dart';
import '../../models/wifi_point.dart';

class WiFiMarkerWidget extends StatelessWidget {
  final WiFiPoint point;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final double rotation;
  
  const WiFiMarkerWidget({
    super.key,
    required this.point,
    this.isHighlighted = false,
    this.rotation = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final markerColor = isHighlighted ? colors.secondary : colors.primary;
  
    return Transform.rotate(
      angle: rotation, 
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: markerColor.withValues(alpha: 0.3),
                      offset: const Offset(0, 1.5),
                      spreadRadius: 0.5,
                      blurStyle:BlurStyle.inner
                    ),
                  ],
                ),
                child: Icon(point.password.isEmpty ? Icons.wifi_tethering_rounded : Icons.wifi_rounded, color: colors.onPrimary, size: 20),
              ),

            // Подпись
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                point.name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      )
    );
  }
}
