import 'package:flutter/services.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:shared_models/shared_models.dart';

/// A contact the rider picked for "Book for someone else".
class PickedContact {
  const PickedContact({this.name, this.phone});
  final String? name;

  /// The number exactly as the phone's address book stores it.
  final String? phone;
}

/// Opens the phone's own contact picker and returns the chosen contact, or
/// null if the rider backed out. An interface so widget tests can fake it.
abstract class ContactPicker {
  Future<PickedContact?> pick();

  /// The picker the passenger dialog uses. Tests swap in a fake.
  static ContactPicker instance = NativeContactPicker();
}

/// The system picker (Android `ACTION_PICK` on phone numbers, iOS
/// `CNContactPickerViewController`). The OS hands back only the one contact
/// the rider chose, so the app needs no READ_CONTACTS permission and no
/// NSContactsUsageDescription.
class NativeContactPicker implements ContactPicker {
  NativeContactPicker([FlutterNativeContactPicker? plugin])
    : _plugin = plugin ?? FlutterNativeContactPicker();
  final FlutterNativeContactPicker _plugin;

  @override
  Future<PickedContact?> pick() async {
    final c = await _plugin.selectPhoneNumber();
    if (c == null) return null;
    final phone =
        c.selectedPhoneNumber ??
        ((c.phoneNumbers?.isNotEmpty ?? false) ? c.phoneNumbers!.first : null);
    return PickedContact(name: c.fullName, phone: phone);
  }
}

/// Thrown when the picker could not be opened at all (no contacts app,
/// platform error). Cancel is not an error: it is a null result.
class ContactPickerUnavailable implements Exception {
  const ContactPickerUnavailable([this.cause]);
  final Object? cause;
}

/// Picks a contact, turning platform failures into [ContactPickerUnavailable].
Future<PickedContact?> pickContactSafely([ContactPicker? picker]) async {
  try {
    return await (picker ?? ContactPicker.instance).pick();
  } on PlatformException catch (e) {
    throw ContactPickerUnavailable(e);
  } on MissingPluginException catch (e) {
    throw ContactPickerUnavailable(e);
  } on UnimplementedError catch (e) {
    throw ContactPickerUnavailable(e);
  }
}

/// Normalises an address-book number to E.164 for [market]: drops spaces,
/// dashes, dots and brackets; keeps a `+` country code; treats a leading
/// `00` as the international prefix; otherwise prefixes the market's dial
/// code (dropping a trunk `0`). Returns null if it is not a dialable number.
String? normalizeContactPhone(String? raw, [Market? market]) {
  if (raw == null) return null;
  var s = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  // A '+' anywhere but the front is noise from the address book.
  if (s.length > 1) s = s[0] + s.substring(1).replaceAll('+', '');
  return (market ?? Market.current).toE164(s);
}
