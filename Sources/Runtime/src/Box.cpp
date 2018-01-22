/// Box.cpp
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#include "silt/Box.h"

void *silt_copyValue(void *dst, void *src) {
  auto srcBox = reinterpret_cast<silt::Value *>(src);
  auto dstBox = reinterpret_cast<silt::Value *>(dst);
  srcBox->copy(dstBox);
  return dstBox;
}

void *silt_moveValue(void *dst, void *src) {
  auto srcBox = reinterpret_cast<silt::Value *>(src);
  auto dstBox = reinterpret_cast<silt::Value *>(dst);
  srcBox->move(dstBox);
  return dstBox;
}

void silt_destroyValue(void *value) {
  auto box = reinterpret_cast<silt::Value *>(value);
  box->destroy();
  delete box;
}

namespace silt {
/// A trivial copy is just a memcpy from the src's value pointer to the dst's.
void *trivialCopy(Value *dst, Value *src) {
  size_t size = dst->getTypeMetadata()->sizeInBytes;
  memcpy(dst->getValue(), src->getValue(), size);
  return dst;
}

/// A trivial move copies the value from the src into the dst, then destroys
/// the src.
void *trivialMove(Value *dst, Value *src) {
  size_t size = dst->getTypeMetadata()->sizeInBytes;
  memcpy(dst->getValue(), src->getValue(), size);
  src->destroy();
  return dst;
}

void *trivialDestroy(Value *value) {

}
}
