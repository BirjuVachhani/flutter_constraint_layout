// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.Pools (upstream pinned in
// UPSTREAM.md). Debug-only pool-membership checks omitted.

/// Simple (non-synchronized) fixed-capacity object pool.
class SimplePool<T> {
  SimplePool(int maxPoolSize)
      : assert(maxPoolSize > 0, 'The max pool size must be > 0'),
        _pool = List<T?>.filled(maxPoolSize, null);

  final List<T?> _pool;
  int _poolSize = 0;

  T? acquire() {
    if (_poolSize > 0) {
      final lastPooledIndex = _poolSize - 1;
      final instance = _pool[lastPooledIndex];
      _pool[lastPooledIndex] = null;
      _poolSize--;
      return instance;
    }
    return null;
  }

  bool release(T instance) {
    if (_poolSize < _pool.length) {
      _pool[_poolSize] = instance;
      _poolSize++;
      return true;
    }
    return false;
  }

  void releaseAll(List<T?> variables, int count) {
    if (count > variables.length) {
      count = variables.length;
    }
    for (var i = 0; i < count; i++) {
      final instance = variables[i];
      if (instance != null && _poolSize < _pool.length) {
        _pool[_poolSize] = instance;
        _poolSize++;
      }
    }
  }
}
