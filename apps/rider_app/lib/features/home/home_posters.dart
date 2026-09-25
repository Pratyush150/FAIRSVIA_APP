import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';

/// The Home's poster carousel: one poster per thing the rider can actually
/// do today, each opening that thing. Copy is market-neutral (no city
/// names, prices or claims the product does not back).
List<PromoBannerData> homePosters({
  required VoidCallback onOffers,
  required VoidCallback onSchedule,
  required VoidCallback onSafety,
  required VoidCallback onRide,
}) => [
  PromoBannerData(
    id: 'poster-offers',
    headline: 'Your ride offers, in one place',
    subline: 'Pick a code and it applies to your next ride.',
    image: PromoPhoto.offersNight,
    art: HomeArt.tag,
    onTap: onOffers,
  ),
  PromoBannerData(
    id: 'poster-schedule',
    headline: "Plan tomorrow's ride tonight",
    subline: 'Pre-book a pickup time in advance.',
    image: PromoPhoto.scheduleDusk,
    art: HomeArt.prebook,
    tone: PromoTone.mint,
    onTap: onSchedule,
  ),
  PromoBannerData(
    id: 'poster-safety',
    headline: 'Help is one tap away',
    subline: 'Add emergency contacts for SOS on every ride.',
    image: PromoPhoto.safetyRide,
    art: HomeArt.someoneElse,
    tone: PromoTone.sun,
    onTap: onSafety,
  ),
  PromoBannerData(
    id: 'poster-share',
    headline: 'Let family follow your ride',
    subline: 'Share a live trip link from the ride screen.',
    image: PromoPhoto.shareTrip,
    art: HomeArt.ride,
    onTap: onRide,
  ),
];
