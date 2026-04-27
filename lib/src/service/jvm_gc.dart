/// GC flags for Java [major].
/// 21+ -> ZGC, 15-20 -> Shenandoah, 8-14 -> unlocked Shenandoah.
List<String> gcFlagsForJavaMajor(int major) {
  if (major >= 21) return const ['-XX:+UseZGC'];
  if (major >= 15) return const ['-XX:+UseShenandoahGC'];
  if (major >= 8) {
    return const ['-XX:+UnlockExperimentalVMOptions', '-XX:+UseShenandoahGC'];
  }
  return const [];
}
