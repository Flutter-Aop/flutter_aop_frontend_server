///Author: YangLang
///Email: yangl@inke.cn
///Date: 2023/8/30

import 'dart:io';

import 'package:kernel/ast.dart';
import 'package:vm/target/flutter.dart';

import 'transformer/string_transformer.dart';
import 'utils/constant_opt_utils.dart';

class ConstantOptTransformer extends FlutterTransformer {
  late List<String> aopPackageList;

  void setAopPackageList(List<String> aopPackageList) {
    print('[aop] aopPackageList: ${aopPackageList.join('、')}');
    this.aopPackageList = aopPackageList;
  }

  bool _needAop(Library library) {
    final Uri importUri = library.importUri;
    final String packageName = importUri.pathSegments.first;
    return aopPackageList.contains(packageName);
  }

  @override
  void transform(Component component, {void Function(String msg)? logger}) {
    List<Library> libraries = component.libraries;
    if (libraries.isEmpty) return;
    Map<String, dynamic>? optMethodMap = searchOptMethod(libraries);
    if (optMethodMap == null) return;
    Library optLibrary = optMethodMap['library'];
    Procedure optMethod = optMethodMap['method'];
    final Map<String, String> optMap = {};
    StringTransformer(optLibrary, optMethod, optMap, _needAop)
        .aopTransform(libraries);
    File('.dart_tool/app_constant_opt.txt').writeAsStringSync(
        optMap.entries.map((e) => e.key + ' -> ' + e.value).join('\n'));
  }
}
