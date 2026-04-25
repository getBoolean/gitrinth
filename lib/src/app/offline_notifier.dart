import 'package:riverpod/riverpod.dart';

class OfflineNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: avoid_positional_boolean_parameters
  void set(bool value) => state = value;
}
