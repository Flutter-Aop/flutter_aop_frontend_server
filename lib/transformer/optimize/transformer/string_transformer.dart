///Author: YangLang
///Email: yanglang116@gmail.com
///Date: 2023/9/3
import 'package:kernel/ast.dart';

import '../utils/constant_opt_utils.dart';
/**
 * 处理字符串项(StringLiteral)：
 * 1、处理字段：Field
 * 2、处理变量声明：VariableDeclaration
 * 3、处理变量赋值：VariableSet
 * 4、处理参数：Arguments
 */

class StringTransformer extends Transformer {
  final Library optExtensionLib;
  final Procedure optMethod;
  final Map<String, String> optMap;
  final bool Function(Library) needAop;

  Library? _cLibrary;

  StringTransformer(
    this.optExtensionLib,
    this.optMethod,
    this.optMap,
    this.needAop,
  );

  void aopTransform(List<Library> libraries) {
    for (Library library in libraries) {
      if (needAop(library)) {
        this._cLibrary = library;
        visitLibrary(library);
        this._cLibrary = null;
      } else {
        visitLibrary(library);
      }
    }
  }

  bool get _needModify => this._cLibrary != null;

  @override
  TreeNode visitField(Field node) {
    Field field = super.visitField(node) as Field;
    if (_needModify && isValidStringLiteral(field.initializer)) {
      //调整 const String constantValue = '123';
      //为： String constantValue = '123'.opt();
      _insertImportIfNeed();
      field.isConst = false;
      StringLiteral literal = field.initializer as StringLiteral;
      field.initializer = _genOptGet(field, literal);
    }
    return field;
  }

  @override
  TreeNode visitVariableDeclaration(VariableDeclaration node) {
    VariableDeclaration varDeclare =
        super.visitVariableDeclaration(node) as VariableDeclaration;
    if (_needModify && isValidStringLiteral(varDeclare.initializer)) {
      //调整 const String constantValue = '123';
      //为： String constantValue = '123'.opt();
      _insertImportIfNeed();
      varDeclare.isConst = false;
      StringLiteral literal = varDeclare.initializer as StringLiteral;
      varDeclare.initializer = _genOptGet(varDeclare, literal);
    }
    return varDeclare;
  }

  @override
  TreeNode visitVariableSet(VariableSet node) {
    VariableSet variableSet = super.visitVariableSet(node) as VariableSet;
    if (_needModify && isValidStringLiteral(variableSet.value)) {
      //调整 constantValue = '123';
      //为： constantValue = '123'.opt();
      _insertImportIfNeed();
      StringLiteral literal = variableSet.value as StringLiteral;
      variableSet.value = _genOptGet(variableSet, literal);
    }
    return variableSet;
  }

  @override
  TreeNode visitConstructorInvocation(ConstructorInvocation node) {
    ConstructorInvocation constructorInv =
        super.visitConstructorInvocation(node) as ConstructorInvocation;
    if (_needModify) {
      constructorInv.isConst = false;
    }
    return constructorInv;
  }

  @override
  TreeNode visitArguments(Arguments node) {
    Arguments arguments = super.visitArguments(node) as Arguments;
    if (_needModify) {
      //调整 print('张三');
      //为： print('张三'.opt(), 20);
      _insertImportIfNeed();
      _adjustArgument(arguments);
    }
    return arguments;
  }

  void _adjustArgument(Arguments arguments) {
    //修改位置参数
    Map<int, Expression> positionalReplace = <int, Expression>{};
    List<Expression> positional = arguments.positional;
    for (int i = 0, j = positional.length; i < j; i++) {
      Expression expr = positional[i];
      if (isValidStringLiteral(expr)) {
        Expression methodGetExpr = _genOptGet(arguments, expr as StringLiteral);
        positionalReplace[i] = methodGetExpr;
      }
    }
    if (positionalReplace.isNotEmpty) {
      _insertImportIfNeed();
      positionalReplace.forEach((index, expr) {
        positional.removeAt(index);
        positional.insert(index, expr);
      });
    }
    //位置表达式
    Map<int, NamedExpression> namedReplace = <int, NamedExpression>{};
    List<NamedExpression> named = arguments.named;
    for (int i = 0, j = named.length; i < j; i++) {
      NamedExpression namedExpr = named[i];
      Expression expr = namedExpr.value;
      if (isValidStringLiteral(expr)) {
        Expression methodGetExpr = _genOptGet(null, expr as StringLiteral);
        NamedExpression newNameExpr = NamedExpression(
          namedExpr.name,
          methodGetExpr,
        );
        newNameExpr.parent = arguments;
        namedReplace[i] = newNameExpr;
      }
    }
    if (namedReplace.isNotEmpty) {
      _insertImportIfNeed();
      namedReplace.forEach((index, namedExpr) {
        named.removeAt(index);
        named.insert(index, namedExpr);
      });
    }
  }

  bool isValidStringLiteral(Expression? expr) {
    return expr is StringLiteral && expr.value.isNotEmpty;
  }

  //修改方法调用
  Expression _genOptGet(TreeNode? parent, StringLiteral literal) {
    String originText = literal.value;
    String newText = encodeStr(originText);
    optMap[originText] = newText;
    Arguments arguments = Arguments([StringLiteral(newText)]);
    Expression expr = StaticInvocation(optMethod, arguments);
    expr.parent = parent;
    return expr;
  }

  //添加导入语句
  void _insertImportIfNeed() {
    List<LibraryDependency> dependencies = _cLibrary!.dependencies;
    for (LibraryDependency dependency in dependencies) {
      if (dependency.importedLibraryReference.node == optExtensionLib) {
        return;
      }
    }
    dependencies.add(LibraryDependency.import(optExtensionLib));
  }
}
