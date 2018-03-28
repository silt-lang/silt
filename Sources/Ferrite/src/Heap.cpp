/// Heap.cpp
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#include "silt/Ferrite/Heap.h"
#include "silt/Ferrite/Errors.h"
#include <cstdio>

void *silt_alloc(size_t bytes) {
  auto ptr = malloc(bytes);
  if (ptr == nullptr) {
    silt::crash("silt_alloc failed to allocate memory");
  }
  return ptr;
}

void silt_dealloc(void *value) {
  free(value);
}
