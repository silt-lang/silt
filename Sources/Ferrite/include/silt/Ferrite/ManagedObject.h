/// ManagedObject.h
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#ifndef SILT_FERRITE_MANAGEDOBJECT_H
#define SILT_FERRITE_MANAGEDOBJECT_H

#include "silt/Ferrite/Defines.h"
#include <functional>

namespace silt {

/// A function that, given an initial value and a size, provides a copy of that
/// value which will be able to be destroyed by an accompanying destroy
/// function.
using SiltCopyFunction = std::function<void *(void *)>;

/// A function that, given an initial value, will destroy that value and render
/// existing references to it useless.
using SiltDestroyFunction = std::function<void (void *)>;

class TypeMetadata;

/// ManagedObject is the base class for any silt type that needs custom copy/
/// destroy behavior.
template <typename T>
struct SILT_PACKED ManagedObject {
  SiltCopyFunction copyImpl;
  SiltDestroyFunction destroyImpl;
  TypeMetadata *metadata;
  T *value;
public:
  ManagedObject(SiltCopyFunction copyImpl, SiltDestroyFunction destroyImpl,
                TypeMetadata *metadata, T *value):
    copyImpl(copyImpl), destroyImpl(destroyImpl),
    metadata(metadata), value(value) {}

  ManagedObject<T> copy() {
    return ManagedObject(copyImpl, destroyImpl,
                         metadata, copyImpl(this->value));
  }
  void destroy() {
    destroyImpl(this->value);
  }
};

// FIXME(harlan): Is this even close to right?
using OpaqueMetadata = ManagedObject<void>;

extern "C" {

/// Copies the underlying ManagedObject pointed to by `value`.
void *silt_copyValue(void *value);

/// Destroys the underlying ManagedObject pointed to by `value`.
void silt_destroyValue(void *value);

OpaqueMetadata *silt_allocEmptyBox();
}

} /* end namespace silt */

#endif
