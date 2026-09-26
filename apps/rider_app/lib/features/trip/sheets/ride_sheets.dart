/// The rider's bottom sheets, one file per phase of the ride.
///
/// They are parts of one library rather than separate imports so the
/// private helpers they share (the money formatter, the SOS button, the
/// warning line) stay private to the sheets instead of becoming public API
/// that anything in the app could reach for.
library;

import '../../home/home_posters.dart';
import '../../home/rider_bottom_nav.dart';
import '../../layout/rider_sheet_heights.dart';
import '../contact_picker.dart';
import '../destination_search_page.dart';
import '../location_service.dart';
import '../price_comparison_card.dart';
import '../ride_status.dart';
import '../ride_status_header.dart';
import '../trip_cubit.dart';
import 'dart:async';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

part 'sheet_shell.dart';
part 'sheet_drag.dart';
part 'glass_phase_sheet.dart';
part 'where_to_sheet.dart';
part 'ride_options_sheet.dart';
part 'ride_details_sheet.dart';
part 'live_ride_sheets.dart';
part 'completed_sheet.dart';
part 'pre_book_page.dart';
