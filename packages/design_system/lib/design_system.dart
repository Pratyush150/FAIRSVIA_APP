/// Shared UI kit: theme, colors, spacing, typography, and reusable widgets.
library;

export 'src/theme/app_colors.dart';
export 'src/theme/app_spacing.dart';
export 'src/theme/app_typography.dart';
export 'src/theme/app_theme.dart';
export 'src/widgets/primary_button.dart';
export 'src/widgets/otp_input.dart';
export 'src/widgets/map_placeholder.dart';
export 'src/widgets/app_map.dart';
export 'src/widgets/connection_banner.dart';

// Re-export the geographic point type so apps get it via design_system.
export 'package:latlong2/latlong.dart' show LatLng;
