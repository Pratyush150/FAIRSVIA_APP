/// Shared UI kit: theme, colors, spacing, typography, and reusable widgets.
library;

export 'src/credits/media_credits.dart';
export 'src/theme/app_brand.dart';
export 'src/theme/app_colors.dart';
export 'src/theme/app_spacing.dart';
export 'src/theme/app_elevation.dart';
export 'src/theme/app_typography.dart';
export 'src/theme/app_theme.dart';
export 'src/theme/app_motion.dart';
export 'src/theme/app_a11y.dart';
export 'src/theme/app_variant.dart';
export 'src/theme/app_glass.dart';
export 'src/theme/app_ink.dart';
export 'src/theme/app_clay3d.dart';

export 'src/widgets/primary_button.dart';
export 'src/widgets/secondary_button.dart';
export 'src/widgets/app_card.dart';
export 'src/widgets/vehicle_glyph.dart';
export 'src/widgets/fairsvia_mark.dart';
export 'src/widgets/app_sheet.dart';
export 'src/widgets/glass_surface.dart';
export 'src/widgets/app_circle_button.dart';
export 'src/widgets/app_icon_badge.dart';
export 'src/widgets/app_status_chip.dart';
export 'src/widgets/app_avatar.dart';
export 'src/widgets/star_rating.dart';
export 'src/widgets/section_header.dart';
export 'src/widgets/empty_state.dart';
export 'src/widgets/message_bubble.dart';
export 'src/widgets/otp_input.dart';
export 'src/widgets/map_placeholder.dart';
export 'src/widgets/app_map.dart';
export 'src/widgets/map_marker_art.dart';
export 'src/widgets/route_progress.dart' hide distanceMeters;
export 'src/widgets/map_geo.dart';
export 'src/widgets/connection_banner.dart';
export 'src/widgets/app_skeleton.dart';
export 'src/widgets/sweep_border.dart';
export 'src/widgets/pulse_radar.dart';
export 'src/widgets/kolam.dart';
export 'src/widgets/local_art.dart';
export 'src/widgets/recenter_pill.dart';
export 'src/widgets/blurred_scrim.dart';
export 'src/widgets/brand_splash.dart';
export 'src/widgets/ink_paper.dart';
export 'src/widgets/route_timeline.dart';
export 'src/widgets/route_snapshot.dart';

// Rider Home building blocks (services row, promo banners, context cards,
// brand footer).
export 'src/widgets/home/home_art.dart';
export 'src/widgets/home/press_scale.dart';
export 'src/widgets/home/service_tile.dart';
export 'src/widgets/home/promo_banner.dart';
export 'src/widgets/home/promo_carousel.dart';
export 'src/widgets/home/context_card.dart';
export 'src/widgets/home/brand_footer.dart';

// Sections for a bottom sheet's pulled-up part (comparison, notes, features).
export 'src/widgets/sheet_extras/sheet_extras.dart';

// Below-the-fold sections for the live ride / booking sheets (progress,
// safety toolkit, fare rows, titled sections).
export 'src/widgets/ride_extras/ride_progress_card.dart';
export 'src/widgets/ride_extras/ride_toolkit_grid.dart';
export 'src/widgets/ride_extras/ride_detail_rows_card.dart';
export 'src/widgets/ride_extras/ride_extras_section.dart';

// Re-export flutter_animate so apps get the `.animate()` API (and our reveal
// helpers) from a single design_system import.
export 'package:flutter_animate/flutter_animate.dart';

// Re-export the geographic point type so apps get it via design_system.
export 'package:latlong2/latlong.dart' show LatLng;

// The one utility-icon family for every app (audit: Phosphor Regular by
// default, Fill only for a state — a rated star, a favourite, a selection).
export 'src/theme/phosphor_icons.dart';
export 'src/widgets/brand_loader.dart';
export 'src/widgets/lottie_moment.dart';
export 'src/widgets/driver_extras/driver_extras.dart';
