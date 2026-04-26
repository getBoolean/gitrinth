// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// Ported into gitrinth from
// https://github.com/dart-lang/pub/blob/master/lib/src/ascii_tree.dart.
// `fromFiles` and the file-size helper are dropped (gitrinth's `deps`
// command renders pre-built maps); the `log.gray` / `emoji` / `platform`
// helpers are inlined against `dart:io` so this stays a self-contained
// utility.

/// A simple library for rendering tree-like structures in Unicode symbols with
/// a fallback to ASCII.
library;

import 'dart:io';

import 'package:collection/collection.dart';

/// Draws a tree from a nested map. Given a map like:
///
///     {
///       "analyzer": {
///         "args": {
///           "collection": ""
///         },
///         "logging": {}
///       },
///       "barback": {}
///     }
///
/// this renders:
///
///     analyzer
///     |-- args
///     |   '-- collection
///     '---logging
///     barback
///
/// Items with no children should have an empty map as the value.
///
/// If [startingAtTop] is `false`, the tree will be shown as:
///
///     |-- analyzer
///     |   '-- args
///     |   |   '-- collection
///     '   '---logging
///     '---barback
String fromMap(Map<String, Map> map, {bool startingAtTop = true}) {
  final buffer = StringBuffer();
  _draw(buffer, '', null, map, depth: startingAtTop ? 0 : 1);
  return buffer.toString();
}

void _drawLine(
  StringBuffer buffer,
  String prefix,
  bool isLastChild,
  String? name,
  bool isRoot,
) {
  // Print lines.
  buffer.write(prefix);
  if (!isRoot) {
    if (isLastChild) {
      buffer.write(_gray(_emoji('└── ', "'-- ")));
    } else {
      buffer.write(_gray(_emoji('├── ', '|-- ')));
    }
  }

  // Print name.
  buffer.writeln(name);
}

String _getPrefix(bool isRoot, bool isLast) {
  if (isRoot) return '';
  if (isLast) return '    ';
  return _gray(_emoji('│   ', '|   '));
}

void _draw(
  StringBuffer buffer,
  String prefix,
  String? name,
  Map<String, Map> children, {
  bool showAllChildren = false,
  bool isLast = false,
  required int depth,
}) {
  // Don't draw a line for the root node.
  if (name != null) _drawLine(buffer, prefix, isLast, name, depth <= 1);

  // Recurse to the children.
  final childNames = children.keys.sorted();

  void drawChild(bool isLastChild, String child) {
    final childPrefix = _getPrefix(depth <= 1, isLast);
    _draw(
      buffer,
      '$prefix$childPrefix',
      child,
      children[child] as Map<String, Map>,
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
  // Non-terminal output (pipes/files) accepts Unicode safely too.
  try {
    return !stdout.hasTerminal;
  } on Object {
    return false;
  }
}

/// Wraps [s] in a gray ANSI sequence when the terminal both supports ANSI
/// and the user has not opted out via `NO_COLOR`. Otherwise returns [s]
/// unchanged. Mirrors dart pub's `log.gray()`.
String _gray(String s) {
  if (!_useAnsi) return s;
  return '\x1b[90m$s\x1b[39m';
}

bool get _useAnsi {
  if (Platform.environment.containsKey('NO_COLOR')) return false;
  try {
    return stdout.hasTerminal && stdout.supportsAnsiEscapes;
  } on Object {
    return false;
  }
}
