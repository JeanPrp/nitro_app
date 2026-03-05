// lib/widgets/simple_charts.dart
import 'package:flutter/material.dart';

class SimpleBarChart extends StatelessWidget {
  final List<BarValue> values; // já ordenado desc
  final String title;
  final String Function(num v) formatter;

  const SimpleBarChart({
    super.key,
    required this.values,
    required this.title,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1 : values.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF0F1724).withOpacity(0.92),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (values.isEmpty)
            Text('Sem dados.', style: TextStyle(color: Colors.white.withOpacity(0.65)))
          else
            ...values.map((b) {
              final pct = (b.value / maxV).clamp(0, 1).toDouble();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        b.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          height: 12,
                          color: Colors.white.withOpacity(0.08),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: pct,
                              child: Container(color: Colors.white.withOpacity(0.35)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 72,
                      child: Text(
                        formatter(b.value),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class BarValue {
  final String label;
  final num value;
  const BarValue(this.label, this.value);
}