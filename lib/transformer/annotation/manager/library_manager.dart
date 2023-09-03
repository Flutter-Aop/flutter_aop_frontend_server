///Author: YangLang
///Email: yangl@inke.cn
///Date: 2023/9/1

import 'package:kernel/ast.dart';

import '../entity/aop_item_info.dart';
import '../entity/aop_mode.dart';
import '../utils/aop_transform_utils.dart';

class LibraryManager {
  LibraryManager._();

  static final LibraryManager _share = LibraryManager._();

  static LibraryManager get share => _share;

  Library? coreLib;
  Procedure? listGetProcedure;
  Procedure? mapGetProcedure;
  Procedure? proceedProcedure;
  Map<String, Library> libraryMap = <String, Library>{};

  void initLibrary(List<Library> libraries) {
    libraries.forEach((Library library) {
      String importUri = library.importUri.toString();
      libraryMap.putIfAbsent(importUri, () => library);
    });
    libraries.forEach((Library library) {
      for (LibraryDependency libraryDependency in library.dependencies) {
        Reference reference = libraryDependency.importedLibraryReference;
        reference.node ??= _getNodeByName(reference.canonicalName);
      }
    });
  }

  List<AopItemInfo> collectAopInfo(Iterable<Library> libraries) {
    List<AopItemInfo> aopItemList = [];
    for (Library library in libraries) {
      final List<Class> classList = library.classes;
      for (Class cls in classList) {
        final bool aspectEnabled = AopUtils.aspectEnable(cls);
        if (!aspectEnabled) continue;
        for (Member member in cls.members) {
          final AopItemInfo? aopItemInfo = _fromMember(member);
          if (aopItemInfo != null) aopItemList.add(aopItemInfo);
        }
      }
    }
    return aopItemList;
  }

  AopItemInfo? _fromMember(Member member) {
    for (Expression annExpr in member.annotations) {
      if (annExpr is ConstantExpression) {
        AopItemInfo? info = _fromConstantExpression(member, annExpr);
        if (info != null) return info;
      } else if (annExpr is ConstructorInvocation) {
        AopItemInfo? info = _fromConstructorInvocation(member, annExpr);
        if (info != null) return info;
      }
    }
    return null;
  }

  //Debug Mode
  AopItemInfo? _fromConstructorInvocation(
    Member member,
    ConstructorInvocation annExpr,
  ) {
    final Class cls = annExpr.targetReference.node!.parent as Class;
    final Library library = cls.parent as Library;
    final AopMode? aopMode = AopUtils.getAopMode(
      cls.name,
      library.importUri.toString(),
    );
    if (aopMode == null) return null;
    List<Expression> posParams = annExpr.arguments.positional;
    final String importUri = (posParams[0] as StringLiteral).value;
    final String clsName = (posParams[1] as StringLiteral).value;
    StringLiteral methodLiteral = StringLiteral('');
    if (posParams.length > 2) {
      methodLiteral = posParams[2] as StringLiteral;
    }
    String methodName = methodLiteral.value;
    bool isRegex = false;
    int? lineNum;
    String? superCls;
    for (NamedExpression namedExpression in annExpr.arguments.named) {
      String argName = namedExpression.name;
      Expression argValue = namedExpression.value;
      if (argName == AopUtils.kAopAnnotationLineNum) {
        lineNum = (argValue as IntLiteral).value - 1;
      }
      if (argName == AopUtils.kAopAnnotationSuperClsName) {
        superCls = (argValue as StringLiteral).value;
      }
      if (argName == AopUtils.kAopAnnotationIsRegex) {
        isRegex = (argValue as BoolLiteral).value;
      }
    }
    bool isStatic = false;
    if (methodName.startsWith(AopUtils.kInstanceMethodPrefix)) {
      int index = AopUtils.kInstanceMethodPrefix.length;
      methodName = methodName.substring(index);
    } else if (methodName.startsWith(AopUtils.kStaticMethodPrefix)) {
      int index = AopUtils.kStaticMethodPrefix.length;
      methodName = methodName.substring(index);
      isStatic = true;
    }
    String fieldName = '';
    if (aopMode == AopMode.FieldGet) {
      final StringLiteral stringLiteral3 = posParams.length > 2
          ? posParams[2] as StringLiteral
          : StringLiteral('');
      fieldName = stringLiteral3.value;
      final BoolLiteral isStaticLiteral = posParams.length > 3
          ? posParams[3] as BoolLiteral
          : BoolLiteral(false);
      isStatic = isStaticLiteral.value;
    }
    member.annotations.remove(annExpr);
    return AopItemInfo(
        importUri: importUri,
        clsName: clsName,
        methodName: methodName,
        isStatic: isStatic,
        aopMember: member,
        mode: aopMode,
        superCls: superCls,
        isRegex: isRegex,
        lineNum: lineNum,
        fieldName: fieldName);
  }

  //Release Mode
  AopItemInfo? _fromConstantExpression(
    Member member,
    ConstantExpression annExpr,
  ) {
    final Constant constant = annExpr.constant;
    if (constant is InstanceConstant) {
      Reference classRef = constant.classReference;
      classRef.node ??= _getNodeByName(classRef.canonicalName);
      constant.fieldValues.forEach((Reference ref, Constant constant) {
        ref.node ??= _getNodeByName(ref.canonicalName);
      });
      String refClsName = classRef.canonicalName!.name;
      String importName = classRef.canonicalName!.parent!.name;
      final AopMode? aopMode = AopUtils.getAopMode(refClsName, importName);
      if (aopMode == null) return null;
      late String importUri;
      late String clsName;
      String? superClsName;
      String? methodName;
      String? fieldName;
      bool isRegex = false;
      bool excludeCoreLib = false;
      int? lineNum;
      bool isStatic = false;
      constant.fieldValues.forEach((Reference ref, Constant constant) {
        String? refFieldName = ref.canonicalName?.name;
        if (constant is StringConstant) {
          final String value = constant.value;
          if (refFieldName == AopUtils.kAopAnnotationImportUri) {
            importUri = value;
          } else if (refFieldName == AopUtils.kAopAnnotationClsName) {
            clsName = value;
          } else if (refFieldName == AopUtils.kAopAnnotationMethodName) {
            methodName = value;
          } else if (refFieldName == AopUtils.kAopAnnotationSuperClsName) {
            superClsName = value;
          } else if (refFieldName == AopUtils.kAopAnnotationFieldName) {
            fieldName = value;
          }
        }
        if (refFieldName == AopUtils.kAopAnnotationLineNum) {
          if (constant is DoubleConstant) {
            final int value = constant.value.toInt();
            lineNum = value - 1;
          } else if (constant is IntConstant) {
            final int value = constant.value;
            lineNum = value - 1;
          }
        }
        if (constant is BoolConstant) {
          final bool value = constant.value;
          if (refFieldName == AopUtils.kAopAnnotationIsRegex) {
            isRegex = value;
          } else if (refFieldName == AopUtils.kAopAnnotationExcludeLib) {
            excludeCoreLib = value;
          } else if (refFieldName == AopUtils.kAopAnnotationIsStatic) {
            isStatic = value;
          }
        }
      });
      if (aopMode != AopMode.FieldGet && methodName != null) {
        if (methodName!.startsWith(AopUtils.kInstanceMethodPrefix)) {
          int startIndex = AopUtils.kInstanceMethodPrefix.length;
          methodName = methodName!.substring(startIndex);
        } else if (methodName!.startsWith(AopUtils.kStaticMethodPrefix)) {
          int startIndex = AopUtils.kStaticMethodPrefix.length;
          methodName = methodName!.substring(startIndex);
          isStatic = true;
        }
      }
      member.annotations.remove(annExpr);
      return AopItemInfo(
          importUri: importUri,
          clsName: clsName,
          methodName: methodName,
          isStatic: isStatic,
          aopMember: member,
          mode: aopMode,
          isRegex: isRegex,
          superCls: superClsName,
          lineNum: lineNum,
          excludeCoreLib: excludeCoreLib,
          fieldName: fieldName);
    }
    return null;
  }

  NamedNode? _getNodeByName(CanonicalName? canonicalName) {
    final List<CanonicalName> nameList = <CanonicalName>[];
    CanonicalName? tmpCanonicalName = canonicalName;
    while (tmpCanonicalName != null) {
      final CanonicalName? parentName = tmpCanonicalName.parent;
      if (parentName != null && tmpCanonicalName.name != '@fields') {
        nameList.insert(0, tmpCanonicalName);
      }
      tmpCanonicalName = parentName;
    }
    final List<NamedNode> nodeList = <NamedNode>[];
    for (int i = 0; i < nameList.length; i++) {
      final CanonicalName name = nameList[i];
      if (i == 0) {
        nodeList.add(libraryMap[name.name] as NamedNode);
      } else if (i == 1) {
        final Library library = nodeList[i - 1] as Library;
        final Class clz = library.classes.firstWhere(
          (Class element) => element.name == name.name,
        );
        nodeList.add(clz);
      } else if (i == 2) {
        final Class cls = nodeList[i - 1] as Class;
        final Field field = cls.fields.firstWhere(
          (Field element) => element.name.text == name.name,
        );
        nodeList.add(field);
      }
    }
    if (nodeList.isEmpty) return null;
    return nodeList.last;
  }

  Procedure? _searchProcedure(
    Library library,
    String clsName,
    String methodName,
  ) {
    for (Class cls in library.classes) {
      final String cClassName = cls.name;
      if (cClassName != clsName) continue;
      for (Procedure procedure in cls.procedures) {
        final String cMethodName = procedure.name.text;
        if (cMethodName == methodName) return procedure;
      }
    }
    return null;
  }

  void setupReference(List<Library> libraries) {
    for (Library library in libraries) {
      if (this.coreLib != null &&
          this.proceedProcedure != null &&
          this.listGetProcedure != null &&
          this.mapGetProcedure != null) {
        return;
      }
      String importUri = library.importUri.toString();
      if (importUri == 'dart.core') {
        this.coreLib = library;
        this.listGetProcedure = _searchProcedure(library, 'List', '[]');
        this.mapGetProcedure = _searchProcedure(library, 'Map', '[]');
      } else if (importUri == AopUtils.kImportUriPointCut) {
        this.proceedProcedure = _searchProcedure(
          library,
          AopUtils.kPointCutClass,
          AopUtils.kProcessMethod,
        );
      }
    }
  }
}
