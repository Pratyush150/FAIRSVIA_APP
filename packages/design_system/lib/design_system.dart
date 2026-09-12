/// Shared UI kit: theme, colors, spacing, typography, and reusable widgets.
library;

export 'src/theme/app_colors.dart';
export 'src/theme/app_spacing.dart';
export 'src/theme/app_elevation.dart';
export 'src/theme/app_typography.dart';
export 'src/theme/app_theme.dart';
export 'src/theme/app_motion.dart';

export 'src/widgets/primary_button.dart';
export 'src/widgets/secondary_button.dart';
export 'src/widgets/app_card.dart';
export 'src/widgets/app_sheet.dart';
export 'src/widgets/app_circle_button.dart';
export 'src/widgets/app_status_chip.dart';
export 'src/widgets/app_avatar.dart';
export 'src/widgets/star_rating.dart';
export 'src/widgets/section_header.dart';
export 'src/widgets/empty_state.dart';
export 'src/widgets/message_bubble.dart';
export 'src/widgets/otp_input.dart';
export 'src/widgets/map_placeholder.dart';
export 'src/widgets/app_map.dart';
export 'src/widgets/route_progress.dart';
export 'src/widgets/map_geo.dart';
export 'src/widgets/connection_banner.dart';
export 'src/widgets/app_skeleton.dart';
export 'src/widgets/pulse_radar.dart';
export 'src/widgets/blurred_scrim.dart';

// Re-export flutter_animate so apps get the `.animate()` API (and our reveal
// helpers) from a single design_system import.
export 'package:flutter_animate/flutter_animate.dart';

// Re-export the geographic point type so apps get it via design_system.
export 'package:latlong2/latlong.dart' show LatLng;
