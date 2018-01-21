/// Defines.h
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#ifndef SILT_RUNTIME_DEFINES_H
#define SILT_RUNTIME_DEFINES_H

#ifdef __cplusplus
#define SILT_BEGIN_DECLS extern "C" {
#define SILT_END_DECLS }
#else
#define SILT_BEGIN_DECLS
#define SILT_END_DECLS
#endif

#define SILT_NORETURN __attribute__((noreturn))

#define SILT_PACKED __attribute__((packed))

#endif /* SILT_RUNTIME_DEFINES_H */
