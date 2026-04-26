// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// Ported into gitrinth from
// https://github.com/dart-lang/pub/blob/master/lib/src/ascii_tree.dart.
// `fromFiles` and the file-size helper are dropped (gitrinth's `deps`
// command renders pre-built maps); the gray styling now flows through
// the [Console] service so `--no-color` / `NO_COLOR` is respected
// uniformly.

/// A simple library for rendering tree-like structures in Unicode symbols with
/// a fallback to ASCII.
library;

import 'dart:io';

import 'package:collection/collection.dart';

import '../service/console.dart';

/// Draws a tree from a nested map. Items with no children should have an
/// empty map as the value. Pass [console] so gray/ANSI handling honors
/// the user's `--color` choice.
String fromMap(
  Map<String, Map> map, {
  required Console console,
  bool startingAtTop = true,
}) {
  final buffer = StringBuffer();
  _draw(buffer, '', null, map, depth: startingAtTop ? 0 : 1, console: console);
  return buffer.toString();
}

void _drawLine(
  StringBuffer buffer,
  String prefix,
  bool isLastChild,
  String? name,
  bool isRoot,
  Console console,
) {
  buffer.write(prefix);
  if (!isRoot) {
    if (isLastChild) {
      buffer.write(console.gray(_emoji('└── ', "'-- ")));
    } else {
      buffer.write(console.gray(_emoji('├── ', '|-- ')));
    }
  }
  buffer.writeln(name);
}

String _getPrefix(bool isRoot, bool isLast, Console console) {
  if (isRoot) return '';
  if (isLast) return '    ';
  return console.gray(_emoji('│   ', '|   '));
}

void _draw(
  StringBuffer buffer,
  String prefix,
  String? name,
  Map<String, Map> children, {
  required Console console,
  bool showAllChildren = false,
  bool isLast = false,
  required int depth,
}) {
  if (name != null) {
    _drawLine(buffer, prefix, isLast, name, depth <= 1, console);
  }

  final childNames = children.keys.sorted();

  void drawChild(bool isLastChild, String child) {
    final childPrefix = _getPrefix(depth <= 1, isLast, console);
    _draw(
      buffer,
      '$prefix$childPrefix',
      child,
      children[child] as Map<String, Map>,
      console: console,
      showAllChildren: showAllChildren,
      isLast: isLastChild,
      depth: depth + 1,
    );
  }

  for (var i = 0; i < childNames.length; i++) {
    drawChild(i == childNames.length - 1, childNames[i]);
  }
}

/// Returns [unicode] when the host terminal can render Unicode box-drawing
/// chars and falls back to [alternative] otherwise. Mirrors dart pub's
/// `emoji()` helper: assume Unicode everywhere except on Windows consoles
/// that aren't Windows Terminal (signaled by `WT_SESSION`).
String _emoji(String unicode, String alternative) =>
    _canUseUnicode ? unicode : alternative;

bool get _canUseUnicode {
  if (!Platform.isWindows) return true;
  if (Platform.environment.containsKey('WT_SESSION')) return true;
  try {
    return !stdout.hasTerminal;
  } on Object {
    return false;
  }
}
