//lib/models/provider_model.dart
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class MapProviderInfo {
  final String id;
  final String name;
  final String subtitle;
  final FaIconData icon;
  final bool requiresKey;
  final String urlTemplate;
  final String? urlTemplateDark;

  const MapProviderInfo({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.requiresKey,
    required this.urlTemplate,
    this.urlTemplateDark,
  });

  static const List<MapProviderInfo> defaultProviders = [
    MapProviderInfo(
      id: 'osm',
      name: 'OpenStreetMap',
      subtitle: 'Открытый, надёжный, бесплатный',
      icon: FontAwesomeIcons.map,
      requiresKey: false,
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    ),
    MapProviderInfo(
      id: 'carto',
      name: 'CartoDB',
      subtitle: 'OpenStreetMaps ещё чище!',
      icon: FontAwesomeIcons.wineGlass,
      requiresKey: false,
      urlTemplate:
          'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
      urlTemplateDark:
          'https://a.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png',
    ),
    MapProviderInfo(
        id: '2gis',
        name: '2GIS',
        subtitle: 'Популярная карта, требуется API-ключ',
        icon: FontAwesomeIcons.compass,
        requiresKey: true,
        urlTemplate:
            'https://tile2.maps.2gis.com/tiles?x={x}&y={y}&z={z}&v=1&key={key}',
        urlTemplateDark:
            'https://tile{n}.maps.2gis.com/v2/tiles/{tileset}/{z}/{x}/{y}.png?key={key}'),
    MapProviderInfo(
      id: 'otm',
      name: 'OpenTopoMap',
      subtitle: 'Топографическая карта, чёткие контуры зданий',
      icon: FontAwesomeIcons.mountain,
      requiresKey: false,
      urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    ),
    MapProviderInfo(
      id: 'ewi',
      name: 'Esri World Imagery',
      subtitle: 'Карта из спутниковых снимков',
      icon: FontAwesomeIcons.satellite,
      requiresKey: false,
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    ),
  ];
}
