// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*@testedFeatures=inference*/
library test;

import 'dart:async';

class MyFuture<T> implements Future<T> {
  MyFuture() {}
  MyFuture.value([x]) {}
  dynamic noSuchMethod(invocation) => null;
  MyFuture<S> then<S>(FutureOr<S> f(T x), {Function? onError}) => throw '';
}

Future f = throw '';
// Instantiates Future<int>
Future<int> t1 = f. /*@typeArgs=int*/ /*@target=Future.then*/ then(
    /*@returnType=MyFuture<int>*/ (/*@ type=dynamic */ _) =>
        new /*@typeArgs=int*/ MyFuture.value('hi'));

// Instantiates List<int>
Future<List<int>> t2 = f. /*@typeArgs=List<int>*/ /*@target=Future.then*/ then(
    /*@returnType=List<int>*/ (/*@ type=dynamic */ _) => /*@typeArgs=int*/ [3]);
Future<List<int>> g2() async {
  return /*@typeArgs=int*/ [3];
}

Future<List<int>> g3() async {
  return new /*@typeArgs=List<int>*/ MyFuture.value(
      /*@typeArgs=int*/ [3]);
}

main() {}
