import 'package:dart_mappable/dart_mappable.dart';

/// Stable serialized identity. Provider capabilities belong to a registry.
final class LoaderId {
  final String name;
  const LoaderId._(this.name);

  factory LoaderId(String name) {
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(name)) {
      throw FormatException('Invalid lowercase loader identity "$name".');
    }
    return LoaderId._(name);
  }

  static const values = [forge, fabric, neoforge, quilt, vanilla];
  static const forge = LoaderId._('forge');
  static const fabric = LoaderId._('fabric');
  static const neoforge = LoaderId._('neoforge');
  static const quilt = LoaderId._('quilt');
  static const vanilla = LoaderId._('vanilla');
  static const iris = LoaderId._('iris');
  static const optifine = LoaderId._('optifine');
  static const canvas = LoaderId._('canvas');
  static const bukkit = LoaderId._('bukkit');
  static const folia = LoaderId._('folia');
  static const paper = LoaderId._('paper');
  static const spigot = LoaderId._('spigot');
  static const sponge = LoaderId._('sponge');
  static const spongeforge = LoaderId._('spongeforge');
  static const spongeneo = LoaderId._('spongeneo');
  static const spongevanilla = LoaderId._('spongevanilla');

  @override
  bool operator ==(Object other) => other is LoaderId && other.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => name;
}

class LoaderIdMapper extends SimpleMapper<LoaderId> {
  const LoaderIdMapper();
  @override
  LoaderId decode(Object value) => LoaderId(value as String);
  @override
  Object encode(LoaderId self) => self.name;
}
