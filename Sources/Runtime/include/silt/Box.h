/// Box.h
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#ifndef SILT_RUNTIME_BOX_H
#define SILT_RUNTIME_BOX_H

#include <cstdlib>
#include <functional>
#include "silt/Defines.h"

#ifdef __cplusplus
namespace silt {

class StringRef {
  char *data;
  size_t length;
};

class Value;

  using SiltCopyFunction = std::function<void *(Value *dst, Value *src)>;
  using SiltMoveFunction = SiltCopyFunction;
  using SiltDestroyFunction = std::function<void (Value *value)>;

struct WitnessTable {
  SiltCopyFunction copy;
  SiltMoveFunction move;
  SiltDestroyFunction destroy;
};

struct TypeMetadata {
  const StringRef name;
  const uint64_t sizeInBytes;
};

/// Represents a typed value that keeps track of its type metadata.
class Value {
private:
  const TypeMetadata *typeMetadata;
  const WitnessTable witnessTable;
  void *value;
public:
  Value(const TypeMetadata *typeMetadata, const WitnessTable witnessTable):
    typeMetadata(typeMetadata), witnessTable(witnessTable) {}

  const TypeMetadata *getTypeMetadata() const {
    return typeMetadata;
  }

  void initializeWithCopy(Value *value) {
    value->copy(this);
  }

  void initializeWithTake(Value *value) {
    value->move(this);
    value->destroy();
  }

  void copy(Value *dst) {
    witnessTable.copy(dst, this);
  }

  void move(Value *dst) {
    witnessTable.move(dst, this);
  }

  void destroy() {
    witnessTable.destroy(this);
  }

  void *getValue() const {
    return value;
  }

  const WitnessTable &getWitnessTable() const {
    return witnessTable;
  }
};

/// A trivial copy operation.
void *trivialCopy(Value *value);

} // end namespace silt
#endif

SILT_BEGIN_DECLS
void *silt_createValue(void *init, void *value);
void *silt_createEmptyValue(void *metadata);
void *silt_copyValue(void *dst, void *src);
void *silt_moveValue(void *dst, void *src);
void silt_destroyValue(void *value);
SILT_END_DECLS

#endif // SILT_RUNTIME_BOX_H
