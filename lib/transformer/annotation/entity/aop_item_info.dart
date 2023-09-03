import 'package:kernel/ast.dart';

import '../entity/aop_mode.dart';
import '../utils/aop_transform_utils.dart';

class AopItemInfo {
  AopItemInfo({
    required this.mode,
    required this.importUri,
    required this.clsName,
    required this.methodName,
    this.isStatic,
    this.aopMember,
    this.isRegex = false,
    this.superCls,
    this.lineNum,
    this.excludeCoreLib = false,
    this.fieldName,
  });

  final AopMode mode;
  final String importUri;
  final String clsName;
  final String? methodName;
  final bool? isStatic;
  final bool isRegex;
  final String? superCls;
  final Member? aopMember;
  final int? lineNum;
  final bool excludeCoreLib;
  final String? fieldName;

  static String uniqueKeyForMethod(
      String importUri, String clsName, String methodName, bool isStatic,
      {int? lineNum}) {
    return (importUri ?? '') +
        AopUtils.kAopUniqueKeySeparator +
        (clsName ?? '') +
        AopUtils.kAopUniqueKeySeparator +
        (methodName ?? '') +
        AopUtils.kAopUniqueKeySeparator +
        (isStatic == true ? '+' : '-') +
        (lineNum != null ? (AopUtils.kAopUniqueKeySeparator + '$lineNum') : '');
  }
}
