import 'package:build/build.dart';

import 'src/asset_strings_builder.dart';

Builder assetStringsBuilder(BuilderOptions options) =>
    AssetStringsBuilder.fromOptions(options);
