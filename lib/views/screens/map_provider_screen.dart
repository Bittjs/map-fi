import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/map_provider_model.dart';
class MapProviderScreen extends StatefulWidget {
  const MapProviderScreen({super.key});

  @override
  State<MapProviderScreen> createState() => _MapProviderScreenState();
}

class _MapProviderScreenState extends State<MapProviderScreen> {
  String? _expandedProviderId; // id провайдера, для которого показано поле ввода
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, GlobalKey<FormState>> _formKeys = {};

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Ленивое создание контроллера и ключа формы для провайдера
  TextEditingController _getController(String id, String currentKey) {
    if (!_controllers.containsKey(id)) {
      _controllers[id] = TextEditingController(text: currentKey);
    }
    return _controllers[id]!;
  }

  GlobalKey<FormState> _getFormKey(String id) {
    if (!_formKeys.containsKey(id)) {
      _formKeys[id] = GlobalKey<FormState>();
    }
    return _formKeys[id]!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 18),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Назад',
        ),
        title: Text(
          'Провайдеры карт',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer<MapProviderModel>(
        builder: (context, model, _) {
          if (!model.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          const providers = MapProviderModel.providers;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colors.onSurface.withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.onSurface.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(providers.length, (index) {
                      final provider = providers[index];
                      final isLast = index == providers.length - 1;
                      final isSelected = model.selectedProviderId == provider.id;
                      final isExpanded = _expandedProviderId == provider.id;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Строка провайдера
                          _ProviderTile(
                            provider: provider,
                            isSelected: isSelected,
                            isExpanded: isExpanded,
                            onTap: () {
                              if (provider.requiresKey) {
                                // Переключаем показ поля ввода
                                setState(() {
                                  _expandedProviderId = isExpanded ? null : provider.id;
                                });
                              } else {
                                model.selectProvider(provider.id);
                                setState(() {
                                  _expandedProviderId = null; // закрываем любое открытое поле
                                });
                              }
                            },
                          ),

                          // Поле ввода ключа (анимированное появление)
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            child: isExpanded
                                ? _ApiKeyInput(
                                    providerId: provider.id,
                                    formKey: _getFormKey(provider.id),
                                    controller: _getController(
                                      provider.id,
                                      model.apiKeys[provider.id] ?? '',
                                    ),
                                    onSubmitted: (key) async {
                                      if (_getFormKey(provider.id).currentState?.validate() ?? false) {
                                        await model.setApiKey(provider.id, key.trim());
                                        setState(() {
                                          _expandedProviderId = null;
                                        });
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('${provider.name} успешно подключен'),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  )
                                : const SizedBox.shrink(),
                          ),

                          // Разделитель, если не последний
                          if (!isLast)
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: colors.onSurface.withValues(alpha: 0.08),
                            ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Виджет строки провайдера (чистый UI)
class _ProviderTile extends StatelessWidget {
  final MapProviderInfo provider;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const _ProviderTile({
    required this.provider,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Иконка провайдера
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.1)
                    : colors.onSurface.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: FaIcon(
                  provider.icon,
                  color: isSelected ? colors.primary : colors.onSurface.withValues(alpha: 0.6),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Текст
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    provider.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.5),
                        ),
                  ),
                ],
              ),
            ),
            // Индикаторы справа
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FaIcon(FontAwesomeIcons.check, color: colors.primary, size: 16),
                  ),
                if (provider.requiresKey)
                  FaIcon(
                    isExpanded
                        ? FontAwesomeIcons.chevronUp
                        : FontAwesomeIcons.chevronDown,
                    size: 14,
                    color: colors.onSurface.withValues(alpha: 0.4),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Виджет поля ввода API-ключа
class _ApiKeyInput extends StatelessWidget {
  final String providerId;
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const _ApiKeyInput({
    required this.providerId,
    required this.formKey,
    required this.controller,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colors.onSurface.withValues(alpha: 0.02),
      child: Form(
        key: formKey,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: TextFormField(
                  controller: controller,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Введите API-ключ',
                    labelText: 'API-ключ',
                    labelStyle: TextStyle(color: colors.onSurface.withValues(alpha: 0.6)),
                    floatingLabelStyle: TextStyle(color: colors.primary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.onSurface.withValues(alpha: 0.12)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.onSurface.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.primary, width: 1.5),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? '' : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: () => onSubmitted(controller.text),
                child: const Text('Подключиться',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}