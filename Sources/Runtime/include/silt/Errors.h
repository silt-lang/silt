/// Errors.h
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#ifndef SILT_RUNTIME_ERRORS_H
#define SILT_RUNTIME_ERRORS_H

#include "silt/Defines.h"

#define silt_assert(cond) ({ \
  if (!cond) { \
    silt::fatalError(#cond); \
  } \
})

SILT_BEGIN_DECLS

SILT_NORETURN
void silt_fatalError(const char *msg);

SILT_NORETURN
void silt_crash();

SILT_END_DECLS

#endif /* SILT_RUNTIME_ERRORS_H */

