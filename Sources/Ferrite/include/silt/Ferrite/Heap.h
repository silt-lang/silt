/// Heap.h
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#ifndef SILT_FERRITE_HEAP_H
#define SILT_FERRITE_HEAP_H

#include "silt/Ferrite/Defines.h"
#include <cstdlib>

namespace silt {
extern "C" {
/// Allocates the provided number of bytes on the heap. This memory is unmanaged
/// and will never be NULL.
/// @param bytes The size, in bytes, of the memory to allocate.
void *silt_alloc(size_t bytes);
/// Deallocates a pointer allocated by \c silt_alloc.
/// @param value The pointer to deallocate.
void *silt_dealloc(void *value);
}
} /* end namespace silt */

#endif
