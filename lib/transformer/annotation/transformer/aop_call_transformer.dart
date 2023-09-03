// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:kernel/ast.dart';

import '../entity/aop_item_info.dart';
import '../entity/aop_mode.dart';
import '../manager/library_manager.dart';
import '../utils/aop_transform_utils.dart';

class AopCallTransformer extends Transformer {
  AopCallTransformer(
    this.infoList,
    this.libraryMap,
    this.uriToSource,
  );

  final List<AopItemInfo> infoList;
  final Map<String, Library> libraryMap;
  final Map<Uri, Source> uriToSource;

  late Library _curLibrary;
  final Map<InvocationExpression, InvocationExpression>
      _invocationExpressionMapping =
      <InvocationExpression, InvocationExpression>{};

  @override
  Library visitLibrary(Library node) {
    _curLibrary = node;
    node.transformChildren(this);
    return node;
  }

  @override
  InvocationExpression visitConstructorInvocation(
      ConstructorInvocation constructorInv) {
    constructorInv.transformChildren(this);
    final Node? node = constructorInv.targetReference.node;

    if (node is Constructor) {
      final Constructor constructor = node;

      final Class cls = constructor.parent as Class;
      final String procedureImportUri =
          (cls.parent as Library).importUri.toString();
      String functionName = '${cls.name}';
      if (constructor.name.text.isNotEmpty) {
        functionName += '.${constructor.name.text}';
      }
      AopItemInfo? aopItemInfo = _filterAopItemInfo(
          infoList, procedureImportUri, cls.name, functionName, true);
      if (aopItemInfo != null &&
          aopItemInfo.mode == AopMode.Call &&
          AopUtils.checkIfSkipAOP(aopItemInfo, _curLibrary) == false) {
        return transformConstructorInvocation(constructorInv, aopItemInfo);
      }
    }
    return constructorInv;
  }

  @override
  StaticInvocation visitStaticInvocation(StaticInvocation staticInvocation) {
    staticInvocation.transformChildren(this);
    Node node = staticInvocation.targetReference.node as Node;
    if (node is Procedure) {
      final Procedure procedure = node;
      final TreeNode treeNode = procedure.parent!;
      if (treeNode is Library) {
        final Library library = treeNode;
        final String libraryImportUri = library.importUri.toString();
        AopItemInfo? aopItemInfo = _filterAopItemInfo(
            infoList, libraryImportUri, '', procedure.name.text, true);
        if (aopItemInfo != null &&
            aopItemInfo.mode == AopMode.Call &&
            AopUtils.checkIfSkipAOP(aopItemInfo, _curLibrary) == false) {
          return transformLibraryStaticMethodInvocation(
              staticInvocation, procedure, aopItemInfo);
        }
      } else if (treeNode is Class) {
        final Class cls = treeNode;
        final String procedureImportUri =
            (cls.parent as Library).importUri.toString();
        AopItemInfo? aopItemInfo = _filterAopItemInfo(
            infoList, procedureImportUri, cls.name, procedure.name.text, true);
        if (aopItemInfo != null &&
            aopItemInfo.mode == AopMode.Call &&
            AopUtils.checkIfSkipAOP(aopItemInfo, _curLibrary) == false) {
          return transformClassStaticMethodInvocation(
              staticInvocation, aopItemInfo);
        }
      }
    }
    return staticInvocation;
  }

  @override
  InstanceInvocation visitInstanceInvocation(InstanceInvocation instanceInv) {
    instanceInv.transformChildren(this);
    final Node node = instanceInv.interfaceTargetReference.node as Node;
    if (node is Procedure) {
      final Procedure procedure = node;
      final Class cls = procedure.parent as Class;
      String importUri = (cls.parent as Library).importUri.toString();
      AopItemInfo? aopItemInfo = _filterAopItemInfo(
          infoList, importUri, cls.name, instanceInv.name.text, false);
      if (aopItemInfo != null &&
          aopItemInfo.mode == AopMode.Call &&
          AopUtils.checkIfSkipAOP(aopItemInfo, _curLibrary) == false) {
        return transformInstanceInv(instanceInv, aopItemInfo);
      }
    }
    return instanceInv;
  }

  //Filter AopInfoMap for specific callSite.
  AopItemInfo? _filterAopItemInfo(List<AopItemInfo> aopItemInfoList,
      String? importUri, String? clsName, String? methodName, bool isStatic) {
    //Reverse sorting so that the newly added Aspect might override the older ones.
    importUri ??= '';
    clsName ??= '';
    methodName ??= '';
    final int aopItemInfoCnt = aopItemInfoList.length;
    for (int i = aopItemInfoCnt - 1; i >= 0; i--) {
      final AopItemInfo aopItemInfo = aopItemInfoList[i];
      if (aopItemInfo.excludeCoreLib &&
          _curLibrary.importUri.toString().startsWith('package:flutter/')) {
        continue;
      }
      if (aopItemInfo.isRegex) {
        //排除hook dart文件
        if (_curLibrary == aopItemInfo.aopMember!.parent!.parent) {
          continue;
        }
        if (RegExp(aopItemInfo.importUri).hasMatch(importUri) &&
            RegExp(aopItemInfo.clsName).hasMatch(clsName) &&
            RegExp(aopItemInfo.methodName!).hasMatch(methodName) &&
            isStatic == aopItemInfo.isStatic) {
          return aopItemInfo;
        }
      } else {
        if (aopItemInfo.importUri == importUri &&
            aopItemInfo.clsName == clsName &&
            aopItemInfo.methodName == methodName &&
            isStatic == aopItemInfo.isStatic) {
          return aopItemInfo;
        }
      }
    }
    return null;
  }

  //Library Static Method Invocation
  StaticInvocation transformLibraryStaticMethodInvocation(
      StaticInvocation staticInvocation,
      Procedure procedure,
      AopItemInfo aopItemInfo) {
    if (_invocationExpressionMapping[staticInvocation] != null) {
      return _invocationExpressionMapping[staticInvocation] as StaticInvocation;
    }

    final Library procedureLibrary = procedure.parent as Library;

    final String stubKey =
        '${AopUtils.kAopStubMethodPrefix}${AopUtils.kPrimaryKeyAopMethod}';
    AopUtils.kPrimaryKeyAopMethod++;

    //更改原始调用
    final Arguments redirectArguments = Arguments.empty();
    final Map<String, String> sourceInfo = AopUtils.calcSourceInfo(
        uriToSource, _curLibrary, staticInvocation.fileOffset);
    AopUtils.concatArgumentsForAopMethod(
        sourceInfo,
        redirectArguments,
        stubKey,
        StringLiteral(procedureLibrary.importUri.toString()),
        procedure,
        staticInvocation.arguments,
        null);
    final StaticInvocation staticInvocationNew =
        StaticInvocation(aopItemInfo.aopMember as Procedure, redirectArguments);

    insertStaticMethod4Pointcut(
        aopItemInfo,
        stubKey,
        LibraryManager.share.proceedProcedure!.parent! as Class,
        staticInvocation,
        procedureLibrary,
        procedure);
    _invocationExpressionMapping[staticInvocation] = staticInvocationNew;
    return staticInvocationNew;
  }

  //Class Constructor Invocation
  StaticInvocation transformConstructorInvocation(
      ConstructorInvocation constructorInvocation, AopItemInfo aopItemInfo) {
    if (_invocationExpressionMapping[constructorInvocation] != null) {
      return _invocationExpressionMapping[constructorInvocation]
          as StaticInvocation;
    }

    final Constructor constructor =
        constructorInvocation.targetReference.node as Constructor;
    final Class procedureClass = constructor.parent as Class;

    final String stubKey =
        '${AopUtils.kAopStubMethodPrefix}${AopUtils.kPrimaryKeyAopMethod}';
    AopUtils.kPrimaryKeyAopMethod++;

    //更改原始调用
    final Arguments redirectArguments = Arguments.empty();
    final Map<String, String> sourceInfo = AopUtils.calcSourceInfo(
        uriToSource, _curLibrary, constructorInvocation.fileOffset);
    final Class currentClass = AopUtils.findClassOfNode(constructorInvocation)!;
    AopUtils.concatArgumentsForAopMethod(
        sourceInfo,
        redirectArguments,
        stubKey,
        StringLiteral(procedureClass.name),
        constructor,
        constructorInvocation.arguments,
        currentClass);

    final StaticInvocation staticInvocationNew =
        StaticInvocation(aopItemInfo.aopMember as Procedure, redirectArguments);

    insertConstructor4Pointcut(
        aopItemInfo,
        stubKey,
        LibraryManager.share.proceedProcedure!.parent as Class,
        constructorInvocation,
        constructorInvocation.targetReference.node!.parent!.parent as Library,
        constructor);
    _invocationExpressionMapping[constructorInvocation] = staticInvocationNew;
    return staticInvocationNew;
  }

  //Class Static Method Invocation
  StaticInvocation transformClassStaticMethodInvocation(
      StaticInvocation staticInvocation, AopItemInfo aopItemInfo) {
    if (_invocationExpressionMapping[staticInvocation] != null) {
      return _invocationExpressionMapping[staticInvocation] as StaticInvocation;
    }

    final Procedure procedure =
        staticInvocation.targetReference.node! as Procedure;
    final Class procedureClass = procedure.parent as Class;

    final String stubKey =
        '${AopUtils.kAopStubMethodPrefix}${AopUtils.kPrimaryKeyAopMethod}';
    AopUtils.kPrimaryKeyAopMethod++;

    //更改原始调用
    final Arguments redirectArguments = Arguments.empty();
    final Map<String, String> sourceInfo = AopUtils.calcSourceInfo(
        uriToSource, _curLibrary, staticInvocation.fileOffset);
    final Class currentClass =
        AopUtils.findClassOfNode(staticInvocation) as Class;

    AopUtils.concatArgumentsForAopMethod(
        sourceInfo,
        redirectArguments,
        stubKey,
        StringLiteral(procedureClass.name),
        procedure,
        staticInvocation.arguments,
        currentClass);

    final StaticInvocation staticInvocationNew =
        StaticInvocation(aopItemInfo.aopMember as Procedure, redirectArguments);

    insertStaticMethod4Pointcut(
        aopItemInfo,
        stubKey,
        LibraryManager.share.proceedProcedure!.parent as Class,
        staticInvocation,
        staticInvocation.targetReference.node!.parent!.parent as Library,
        procedure);
    _invocationExpressionMapping[staticInvocation] = staticInvocationNew;
    return staticInvocationNew;
  }

  //Instance Method Invocation
  InstanceInvocation transformInstanceInv(
    InstanceInvocation instanceInv,
    AopItemInfo aopItemInfo,
  ) {
    if (_invocationExpressionMapping[instanceInv] != null) {
      return _invocationExpressionMapping[instanceInv] as InstanceInvocation;
    }
    final String? targetMethodName = instanceInv.name.text;
    Procedure targetMethod =
        instanceInv.interfaceTargetReference.node as Procedure;
    Class targetClass = targetMethod.parent as Class;
    Class methodImplClass = targetClass;
    if (targetClass.flags & Class.FlagAbstract != 0) {
      Library? targetLibrary = targetClass.parent as Library;
      for (Class cls in targetLibrary.classes) {
        final String clsName = cls.name;
        if (cls.flags & Class.FlagAbstract != 0) continue;
        bool matches = false;
        for (Supertype superType in cls.implementedTypes) {
          if (superType.className.node == targetClass) {
            matches = true;
          }
        }
        if (!matches || (clsName != '_${targetClass.name}')) {
          continue;
        }
        methodImplClass = cls;
        for (Procedure procedure in cls.procedures) {
          final String methodName = procedure.name.text;
          if (methodName == targetMethodName) {
            targetMethod = procedure;
            break;
          }
        }
      }
    }
    final String stubKey =
        '${AopUtils.kAopStubMethodPrefix}${AopUtils.kPrimaryKeyAopMethod}';
    AopUtils.kPrimaryKeyAopMethod++;

    //更改原始调用
    final Arguments redirectArguments = Arguments.empty();
    final Map<String, String> sourceInfo = AopUtils.calcSourceInfo(
        uriToSource, _curLibrary, instanceInv.fileOffset);
    final Class currentClass = AopUtils.findClassOfNode(instanceInv)!;

    AopUtils.concatArgumentsForAopMethod(
        sourceInfo,
        redirectArguments,
        stubKey,
        instanceInv.receiver,
        targetMethod,
        instanceInv.arguments,
        currentClass);

    final Class cls = aopItemInfo.aopMember!.parent as Class;
    final ConstructorInvocation redirectConstructorInvocation =
        ConstructorInvocation.byReference(
            cls.constructors.first.reference, Arguments(<Expression>[]));
    final InstanceInvocation methodInvocationNew = InstanceInvocation(
        InstanceAccessKind.Instance,
        redirectConstructorInvocation,
        aopItemInfo.aopMember!.name,
        redirectArguments,
        interfaceTarget: aopItemInfo.aopMember! as Procedure,
        functionType: aopItemInfo.aopMember!.getterType as FunctionType);
    AopUtils.insertLibraryDependency(
        _curLibrary, aopItemInfo.aopMember!.parent!.parent as Library);

    insertInstanceMethod4Pointcut(
        instanceInv,
        aopItemInfo,
        stubKey,
        LibraryManager.share.proceedProcedure!.parent as Class,
        methodImplClass,
        targetMethod);
    _invocationExpressionMapping[instanceInv] = methodInvocationNew;
    return methodInvocationNew;
  }

  bool insertConstructor4Pointcut(
      AopItemInfo aopItemInfo,
      String stubKey,
      Class pointCutClass,
      ConstructorInvocation constructorInvocation,
      Library originalLibrary,
      Member originalMember) {
    //Add library dependency
    AopUtils.insertLibraryDependency(
        pointCutClass.parent as Library, originalLibrary);
    //Add new Procedure

    final ConstructorInvocation constructorInvocation = ConstructorInvocation(
        originalMember as Constructor,
        AopUtils.concatArguments4PointcutStubCall(originalMember, aopItemInfo));

    final bool shouldReturn = !(originalMember.function.returnType is VoidType);
    createPointcutStubProcedure(
        aopItemInfo,
        stubKey,
        pointCutClass,
        AopUtils.createProcedureBodyWithExpression(
            constructorInvocation, shouldReturn),
        shouldReturn);
    return true;
  }

  bool insertStaticMethod4Pointcut(
      AopItemInfo aopItemInfo,
      String stubKey,
      Class pointCutClass,
      StaticInvocation originalStaticInvocation,
      Library originalLibrary,
      Member originalMember) {
    //Add library dependency
    AopUtils.insertLibraryDependency(
        pointCutClass.parent as Library, originalLibrary);
    //Add new Procedure
    final StaticInvocation staticInvocation = StaticInvocation(
        originalMember as Procedure,
        AopUtils.concatArguments4PointcutStubCall(originalMember, aopItemInfo),
        isConst: originalMember.isConst);
    final bool shouldReturn = !(originalMember.function.returnType is VoidType);
    createPointcutStubProcedure(
        aopItemInfo,
        stubKey,
        pointCutClass,
        AopUtils.createProcedureBodyWithExpression(
            staticInvocation, shouldReturn),
        shouldReturn);
    return true;
  }

  bool insertInstanceMethod4Pointcut(
      InstanceInvocation originalInvocation,
      AopItemInfo aopItemInfo,
      String stubKey,
      Class pointCutClass,
      Class procedureImpl,
      Procedure originalProcedure) {
    late Field targetFiled;
    for (Field field in pointCutClass.fields) {
      if (field.name.text == 'target') {
        targetFiled = field;
      }
    }

    //Add library dependency
    //Add new Procedure
    final InstanceInvocation mockedInvocation = InstanceInvocation(
        InstanceAccessKind.Instance,
        AsExpression(
            InstanceGet(
                InstanceAccessKind.Instance, ThisExpression(), Name('target'),
                resultType: targetFiled.type as DartType,
                interfaceTarget: targetFiled),
            InterfaceType(procedureImpl, Nullability.legacy)),
        originalProcedure.name,
        AopUtils.concatArguments4PointcutStubCall(
            originalProcedure, aopItemInfo),
        interfaceTarget: originalProcedure,
        functionType: originalInvocation.functionType);
    final bool shouldReturn =
        !(originalProcedure.function.returnType is VoidType);
    createPointcutStubProcedure(
        aopItemInfo,
        stubKey,
        pointCutClass,
        AopUtils.createProcedureBodyWithExpression(mockedInvocation,
            !(originalProcedure.function.returnType is VoidType)),
        shouldReturn);
    return true;
  }

  //Will create stub and insert call branch in proceed.
  void createPointcutStubProcedure(
    AopItemInfo aopItemInfo,
    String stubKey,
    Class pointCutClass,
    Statement bodyStatements,
    bool shouldReturn,
  ) {
    final Procedure procedure = AopUtils.createStubProcedure(
        Name(stubKey, LibraryManager.share.proceedProcedure!.name.library),
        aopItemInfo,
        LibraryManager.share.proceedProcedure as Procedure,
        bodyStatements,
        shouldReturn);
    pointCutClass.procedures.add(procedure);
    if (procedure.isStatic) {
      procedure.parent = pointCutClass.parent;
    } else {
      procedure.parent = pointCutClass;
    }

    AopUtils.insertProceedBranch(pointCutClass, procedure, shouldReturn);
  }

  void aopTransform(List<Library> libraries) {
    for (int i = 0; i < libraries.length; i++) {
      final Library library = libraries[i];
      visitLibrary(library);
    }
  }
}
