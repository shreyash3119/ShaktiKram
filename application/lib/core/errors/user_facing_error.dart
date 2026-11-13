/// An error whose message is written for the person using the app and can be shown as it is.
abstract interface class UserFacingError implements Exception {
  String get message;
}
