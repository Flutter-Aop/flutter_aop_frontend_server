import 'package:kernel/ast.dart';
import 'package:vm/target/flutter.dart';

import './entity/aop_item_info.dart';
import './entity/aop_mode.dart';
import './manager/library_manager.dart';
import './transformer/aop_add_transformer.dart';
import './transformer/aop_call_transformer.dart';
import './transformer/aop_execute_transformer.dart';
import './transformer/aop_field_get_transformer.dart';
import './transformer/aop_inject_transformer.dart';

class AnnotationTransformer extends FlutterTransformer {
  @override
  void transform(Component program, {void Function(String msg)? logger}) {
    List<Library> libraries = program.libraries;
    if (libraries.isEmpty) return;
    //优化library的引用
    LibraryManager.share.initLibrary(libraries);
    //建立核心库引用
    LibraryManager.share.setupReference(libraries);
    //收集Aspect信息
    List<AopItemInfo> aopList = LibraryManager.share.collectAopInfo(libraries);
    //拆分AopInfo
    final Map<Uri, Source> uriToSource = program.uriToSource;
    Map<String, Library> libMap = LibraryManager.share.libraryMap;
    // Aop call transformer
    final callList = searchByMode(aopList, AopMode.Call);
    if (callList.isNotEmpty) {
      AopCallTransformer(callList, libMap, uriToSource).aopTransform(libraries);
    }
    // Aop add transformer
    final addList = searchByMode(aopList, AopMode.Add);
    if (addList.isNotEmpty) {
      AopAddTransformer(addList, uriToSource).aopTransform(libraries);
    }
    // Aop execute transformer
    final execList = searchByMode(aopList, AopMode.Execute);
    if (execList.isNotEmpty) {
      AopExecuteTransformer(execList, libMap, uriToSource).aopTransform();
    }
    // Aop inject transformer
    final injectList = searchByMode(aopList, AopMode.Inject);
    if (injectList.isNotEmpty) {
      AopInjectTransformer(injectList, libMap, uriToSource).aopTransform();
    }
    final fieldGetList = searchByMode(aopList, AopMode.FieldGet);
    if (fieldGetList.isNotEmpty) {
      AopFieldGetTransformer(fieldGetList).aopTransform(libraries);
    }
  }

  List<AopItemInfo> searchByMode(List<AopItemInfo> list, AopMode mode) {
    return list.where((element) => element.mode == mode).toList();
  }
}
