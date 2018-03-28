/// Errors.h
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#ifndef SILT_FERRITE_ERRORS_H

#include "silt/Ferrite/Defines.h"

namespace silt {

/// Causes the process to terminate after printing  
SILT_NORETURN
void crash(const char *message);

} // end namespace silt

#endif
