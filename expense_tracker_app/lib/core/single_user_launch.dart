const bool launchEnableDataTransferTools = false;

List<T> filterSingleUserLaunchPackages<T>(
  Iterable<T> packages, {
  required bool Function(T package) isFamilyPackage,
}) {
  return packages.where((package) => !isFamilyPackage(package)).toList();
}
