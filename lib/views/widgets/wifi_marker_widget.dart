// lib/views/widgets/wifi_marker_widget.dart

import 'package:flutter/material.dart';
import '../../models/wifi_point.dart';

/// Кастомный маркер Wi-Fi точки: иконка + подпись названия.
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
    final color = isHighlighted ? Colors.amber : const Color.fromARGB(255, 22, 160, 133);
  
    return Transform.rotate(
      angle: rotation, 
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Иконка в цветном круге
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(point.password.isEmpty ? Icons.wifi_tethering : Icons.wifi, color: Colors.white, size: 20),
            ),

          // Подпись
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              point.name,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
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
