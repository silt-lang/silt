/// Errors.cpp
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
#include "silt/Ferrite/Errors.h"
#include <cstdio>
#include <cstdlib>

void silt::crash(const char *message) {
  fputs(message, stderr);
  fputc('\n', stderr);
  abort();
}
