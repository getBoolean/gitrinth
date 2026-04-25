import 'dart:io';

import '../cli/exceptions.dart';

/// Adoptium-style host platform descriptor. [os] is one of `windows`,
/// `linux`, `mac`; [arch] is one of `x64`, `aarch64`.
class HostPlatform {
  final String os;
  final String arch;
  const HostPlatform({required this.os, required this.arch});

  bool get isWindows => os == 'windows';

  @override
  String toString() => 'HostPlatform($os, $arch)';
}

/// Test-only override for [detectHostPlatform]. Mirrors Flutter's
/// `debugDefaultTargetPlatformOverride` pattern: a global mutable that
/// the detector consults first. Set it in `setUp`, clear it in
/// `tearDown`. Production code never touches this — leave it null and
/// detection reads the real [Platform].
HostPlatform? debugHostPlatformOverride;

/// Detects the current host's OS + CPU architecture in the keys
/// Adoptium expects. Honors [debugHostPlatformOverride] first; falls
/// back to real [Platform] / `uname -m` / `PROCESSOR_ARCHITECTURE`
/// detection. [environment] is the env map to read from for Windows
/// arch detection (defaults to [Platform.environment] if omitted).
HostPlatform detectHostPlatform({Map<String, String>? environment}) {
  final override = debugHostPlatformOverride;
  if (override != null) return override;

  final env = environment ?? Platform.environment;
  final os = _detectOs();
  final arch = _detectArch(os, env);
  return HostPlatform(os: os, arch: arch);
}

String _detectOs() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'mac';
  if (Platform.isLinux) return 'linux';
  throw UserError('unsupported OS: ${Platform.operatingSystem}');
}

String _detectArch(String os, Map<String, String> env) {
  if (os == 'windows') {
    final pa = (env['PROCESSOR_ARCHITECTURE'] ?? '').toUpperCase();
    final pa64 = (env['PROCESSOR_ARCHITEW6432'] ?? '').toUpperCase();
    if (pa == 'ARM64' || pa64 == 'ARM64') return 'aarch64';
    // 32-bit-only Windows hosts are vanishingly rare; default to x64
    // so the download URL is well-formed and Adoptium's 404 surfaces
    // clearly if no build exists.
    return 'x64';
  }
  try {
    final result = Process.runSync('uname', ['-m']);
    final raw = (result.stdout as String).trim().toLowerCase();
    if (raw == 'x86_64' || raw == 'amd64') return 'x64';
    if (raw == 'aarch64' || raw == 'arm64') return 'aarch64';
    throw UserError(
      'no Temurin build for arch "$raw" on $os; pass --java <path>.',
    );
  } on ProcessException {
    throw const UserError(
      'failed to run `uname -m` to detect CPU architecture; '
      'pass --java <path>.',
    );
  }
}
