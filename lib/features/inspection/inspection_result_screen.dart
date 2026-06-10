import 'package:flutter/material.dart';
import 'package:vazamento_detector/features/inspection/inspection_result.dart';

class InspectionResultScreen extends StatelessWidget {
  const InspectionResultScreen({
    required this.result,
    super.key,
  });

  final InspectionResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado da analise'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              result.imageBytes,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Leitura visual',
            children: [
              _MetricRow(
                label: 'Sinal vermelho',
                value: result.visualAnalysis.redSignalPixels.toString(),
              ),
              _MetricRow(
                label: 'Cores quentes',
                value: result.visualAnalysis.hotColorPixels.toString(),
              ),
              _MetricRow(
                label: 'Areas escuras',
                value: result.visualAnalysis.darkAreaPixels.toString(),
              ),
              _MetricRow(
                label: 'Status',
                value: result.visualAnalysis.message ?? 'Sem alerta visual',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'IA local',
            children: [
              _MetricRow(label: 'Status', value: result.aiStatus),
              if (result.aiResult != null) ...[
                _MetricRow(
                  label: 'Atividade',
                  value:
                      '${(result.aiResult!.activeRatio * 100).toStringAsFixed(1)}%',
                ),
                _MetricRow(
                  label: 'Pico',
                  value:
                      '${(result.aiResult!.maxScore * 100).toStringAsFixed(0)}%',
                ),
                _MetricRow(
                  label: 'Tempo',
                  value:
                      '${(result.aiResult!.inferenceMicros / 1000).toStringAsFixed(1)} ms',
                ),
              ],
              if (result.hasAiError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                    result.aiErrorDetail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
