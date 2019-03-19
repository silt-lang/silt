/// ManagedObject.cpp
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#include "silt/Ferrite/ManagedObject.h"

using namespace silt;

namespace { // Begin anonymous namespace.

  struct _SiltEmptyBox {
    silt::OpaqueMetadata header;
  };

  silt::OpaqueMetadata _emptyBoxStorageMetadata(nullptr, nullptr, nullptr, nullptr);

  /// The singleton empty box storage object.
  _SiltEmptyBox _EmptyBoxStorage = {
    _emptyBoxStorageMetadata,
  };

} // End anonymous namespace.

silt::OpaqueMetadata *silt::silt_allocEmptyBox() {
  auto OpaqueMetadata = reinterpret_cast<silt::OpaqueMetadata*>(&_EmptyBoxStorage);
//  swift_retain(OpaqueMetadata);
  return OpaqueMetadata;
}
