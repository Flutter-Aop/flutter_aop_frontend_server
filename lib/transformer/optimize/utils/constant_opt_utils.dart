///Author: YangLang
///Email: yanglang116@gmail.com
///Date: 2023/9/3
import 'dart:convert';

import 'package:kernel/ast.dart';

const String LIB_OPT = 'package:flutter_aop/extension/ext_string_opt.dart';
const String METHOD_OPT = 'opt';

Map<String, dynamic>? searchOptMethod(List<Library> libraries) {
  for (Library lib in libraries) {
    String importLib = lib.importUri.toString();
    if (importLib != LIB_OPT) continue;
    Extension optExt = lib.extensions.first;
    for (ExtensionMemberDescriptor memberDesc in optExt.members) {
      final String methodName = memberDesc.name.text;
      if (methodName == METHOD_OPT) {
        return {
          'library': lib,
          'method': memberDesc.member.asProcedure,
        };
      }
    }
  }
  return null;
}

String encodeStr(String origin) {
  List<int> bytes = utf8.encode(origin);
  return base64Encode(bytes);
}
