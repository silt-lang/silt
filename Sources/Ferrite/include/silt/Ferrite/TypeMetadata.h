/// TypeMetadata.h
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#ifndef SILT_FERRITE_TYPEMETADATA_H
#define SILT_FERRITE_TYPEMETADATA_H

#include "silt/Ferrite/ManagedObject.h"
#include <cstdlib>

namespace silt {
extern "C" {

}

enum class TypeMetadataKind : uint8_t {
  Union,
  Enum,
  Record,
  Function,
  TypeMetadata,
}

class SILT_PACKED TypeMetadata {
  ManagedObject *valueWitnessTable;
  const char *mangledName;
  
};

} /* end namespace silt */

#endif
