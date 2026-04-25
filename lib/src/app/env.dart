import 'dart:io';

import 'package:riverpod/riverpod.dart';

final environmentProvider = Provider<Map<String, String>>(
  (ref) => Platform.environment,
);
