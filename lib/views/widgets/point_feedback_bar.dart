// lib/views/widgets/point_feedback_bar.dart
// Карточка агрегированных отзывов по выбранной точке:
// зелёная/красная полоса (проверки/жалобы), счётчики, период,
// предупреждение о недоступности и действия (верификация / жалоба).

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart' show FaIcon, FaIconData, FontAwesomeIcons;

import '../../models/point_stats.dart';
import '../../models/wifi_point.dart';
import '../../services/api_client.dart';
import '../../viewmodels/map_viewmodel.dart';

class PointFeedbackBar extends StatefulWidget {
  final WiFiPoint point;
  final MapViewModel viewModel;

  const PointFeedbackBar({
    super.key,
    required this.point,
    required this.viewModel,
  });

  @override
  State<PointFeedbackBar> createState() => _PointFeedbackBarState();
}

class _PointFeedbackBarState extends State<PointFeedbackBar> {
  static const _windowOptions = [7, 30, 90, 180];
  static const _green = Color(0xFF2E7D32);
  static const _red = Color(0xFFC62828);

  int _days = 30;
  PointStats _stats = PointStats.empty;
  PointProximity _proximity = PointProximity.far;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await widget.viewModel.loadPointStats(widget.point, days: _days);
    final proximity = await widget.viewModel.proximityOf(widget.point);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _proximity = proximity;
      _loading = false;
    });
  }

  void _changeWindow(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  static String _windowLabel(int days) => switch (days) {
        7 => '7 дней',
        30 => '30 дней',
        90 => '90 дней',
        _ => '6 мес.',
      };

  Future<void> _verify() async {
    final ok = await widget.viewModel.verifyPoint(widget.point);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Точка верифицирована'
            : 'Не удалось верифицировать: подключитесь к сети ${widget.point.name}'),
      ),
    );
    if (ok) _load();
  }

  Future<void> _complain() async {
    const options = [
      _ComplaintOption(
        FeedbackTypes.wrongPassword,
        'Неверный пароль',
        FontAwesomeIcons.key,
      ),
      _ComplaintOption(
        FeedbackTypes.pointNotFound,
        'Точки нет в этом месте',
        FontAwesomeIcons.mapPin,
      ),
      _ComplaintOption(
        FeedbackTypes.spamFake,
        'Спам / фейковая точка',
        FontAwesomeIcons.bullhorn,
      ),
      _ComplaintOption(
        FeedbackTypes.other,
        'Другое',
        FontAwesomeIcons.ellipsis,
      ),
    ];
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Жалоба на «${widget.point.name}»',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              for (final o in options)
                ListTile(
                  leading: FaIcon(o.icon, size: 18),
                  title: Text(o.label),
                  onTap: () => Navigator.pop(ctx, o.type),
                ),
            ],
          ),
        );
      },
    );
    if (type == null || !mounted) return;

    await widget.viewModel.submitFeedback(widget.point, type);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Спасибо, отзыв отправлен')),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final checks = _stats.checks;
    final complaints = _stats.complaints;
    final total = checks + complaints;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.point.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButton<int>(
                  value: _days,
                  underline: const SizedBox(),
                  isDense: true,
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: colors.surface,
                  iconEnabledColor:
                      colors.onSurface.withValues(alpha: 0.8),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  items: [
                    for (final d in _windowOptions)
                      DropdownMenuItem(value: d, child: Text(_windowLabel(d))),
                  ],
                  onChanged: (d) => d == null ? null : _changeWindow(d),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Counter(
                icon: FontAwesomeIcons.circleCheck,
                color: _green,
                label: 'Проверок: $checks',
              ),
              const SizedBox(width: 16),
              _Counter(
                icon: FontAwesomeIcons.triangleExclamation,
                color: _red,
                label: 'Жалоб: $complaints',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const LinearProgressIndicator()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (total == 0) {
                  return Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }
                final greenW = width * checks / total;
                final redW = width - greenW;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        if (greenW > 0)
                          Container(width: greenW, color: _green),
                        if (redW > 0)
                          Container(width: redW, color: _red),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (_stats.likelyUnavailable) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  FaIcon(FontAwesomeIcons.triangleExclamation,
                      size: 14, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Возможно, точка не доступна (много жалоб о том, '
                      'что её нет).',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (_proximity == PointProximity.connected)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _verify,
                style: FilledButton.styleFrom(backgroundColor: _green),
                icon: const FaIcon(FontAwesomeIcons.circleCheck, size: 16),
                label: const Text('Верифицировать'),
              ),
            )
          else if (_proximity == PointProximity.nearby)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _complain,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: BorderSide(color: _red.withValues(alpha: 0.6)),
                ),
                icon: const FaIcon(FontAwesomeIcons.triangleExclamation,
                    size: 16),
                label: const Text('Пожаловаться'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: Text(
                'Подойдите к точке ближе 50 м, чтобы проверить её '
                'или оставить жалобу.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComplaintOption {
  final String type;
  final String label;
  final FaIconData icon;

  const _ComplaintOption(this.type, this.label, this.icon);
}

class _Counter extends StatelessWidget {
  final FaIconData icon;
  final Color color;
  final String label;

  const _Counter({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}