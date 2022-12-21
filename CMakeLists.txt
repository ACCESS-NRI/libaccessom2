# https://cmake.org/cmake/help/v3.6/module/FindPkgConfig.html
cmake_minimum_required(VERSION 3.6 FATAL_ERROR)
project(yatm VERSION 2.0.202212 LANGUAGES Fortran)

message("---- PROJECT_VERSION: " '${PROJECT_VERSION}')
add_definitions( -DCMAKE_YATM_VERSION='${PROJECT_VERSION}' )

# set output paths for modules, archives, and executables
set(CMAKE_Fortran_MODULE_DIRECTORY ${PROJECT_BINARY_DIR}/include)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# if build type not specified, default to release
# set(CMAKE_BUILD_TYPE "Debug")
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "Release")
endif()

cmake_host_system_information(RESULT my_fqdn QUERY FQDN)
message("---- Detected FQDN: " ${my_fqdn})
cmake_host_system_information(RESULT my_ncores QUERY NUMBER_OF_LOGICAL_CORES)
message("---- Detected NUMBER_OF_LOGICAL_CORES: " ${my_ncores})

if (MPIFORT_EXE STREQUAL "MPIFORT_EXE-NOTFOUND")
  message("mpifort not found, searching for MPI libraries" )
  find_package(MPI)
else()
  message("mpifort executable found: " ${MPIFORT_EXE})
  message("Will assume system MPI implementation is sound. Remove mpifort from PATH to automatically configure MPI")
  if (CMAKE_FC_COMPILER STREQUAL "scorep-mpif90")
    set(MPI_FORTRAN_COMPILER scorep-mpif90)
    set(CMAKE_Fortran_COMPILER scorep-mpif90)
  else()
    set(MPI_FORTRAN_COMPILER mpifort)
    set(CMAKE_Fortran_COMPILER mpifort)
  endif()
endif()

# compiler flags for gfortran
if(CMAKE_Fortran_COMPILER_ID MATCHES GNU)
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -std=f2008 -Wall -fdefault-real-8 -ffpe-trap=invalid,zero,overflow")
  set(CMAKE_Fortran_FLAGS_DEBUG "-O0 -g -pg -fbounds-check -fbacktrace")
  set(CMAKE_Fortran_FLAGS_RELEASE "-O3")
endif()

# compiler flags for ifort
if(CMAKE_Fortran_COMPILER_ID MATCHES Intel)
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -r8 -fpe0 -fp-model precise -fp-model source -align all -traceback")
  set(CMAKE_Fortran_FLAGS_DEBUG "-g3 -O0 -check all")
  set(CMAKE_Fortran_FLAGS_RELEASE "-g3 -O2 -axCORE-AVX2 -debug all -check none -qopt-report=5 -qopt-report-annotate")
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(NETCDF REQUIRED IMPORTED_TARGET "netcdf-fortran")
message("---- NETCDF_INCLUDEDIR: " ${NETCDF_INCLUDEDIR})
message("---- NETCDF_INCLUDE_DIRS: " ${NETCDF_INCLUDE_DIRS})
message("---- FOUND: " ${NETCDF_FOUND})
message("---- LIBRARIES: " ${NETCDF_LIBRARIES})
message("---- LINK_LIBRARIES: " ${NETCDF_LINK_LIBRARIES})
message("---- LIBRARY_DIRS: " ${NETCDF_LIBRARY_DIRS})
message("---- LDFLAGS: " ${NETCDF_LDFLAGS})
message("---- LDFLAGS_OTHER: " ${NETCDF_LDFLAGS_OTHER})
message("---- INCLUDE_DIRS: " ${NETCDF_INCLUDE_DIRS})
message("---- CFLAGS: " ${NETCDF_CFLAGS})
message("---- CFLAGS_OTHER: " ${NETCDF_CFLAGS_OTHER})
include_directories(${NETCDF_INCLUDEDIR})

# Back to using the upstream version as the the bug is apparently not
# reproducible since intel-compiler/2019.5.281 and intel-compiler/2020.0.166:
# https://github.com/wavebitscientific/datetime-fortran/issues/51
pkg_check_modules(DATETIME REQUIRED IMPORTED_TARGET "datetime-fortran")
include_directories(${DATETIME_INCLUDE_DIRS})
message("DATETIME_INCLUDEDIR: " ${DATETIME_INCLUDEDIR})
message("DATETIME_INCLUDE_DIRS: " ${DATETIME_INCLUDE_DIRS})

pkg_check_modules(JSONFORTRAN REQUIRED IMPORTED_TARGET "json-fortran")
include_directories(${JSONFORTRAN_INCLUDE_DIRS})
message("JSONFORTRAN_INCLUDEDIR: " ${JSONFORTRAN_INCLUDEDIR})
message("JSONFORTRAN_INCLUDE_DIRS: " ${JSONFORTRAN_INCLUDE_DIRS})

pkg_check_modules(OASIS3MCT REQUIRED IMPORTED_TARGET "oasis3-mct")
include_directories(${OASIS3MCT_INCLUDE_DIRS})
message("OASIS3MCT_INCLUDEDIR: " ${OASIS3MCT_INCLUDEDIR})
message("OASIS3MCT_INCLUDE_DIRS: " ${OASIS3MCT_INCLUDE_DIRS})

pkg_check_modules(OASIS3MPEU REQUIRED IMPORTED_TARGET "oasis3-mpeu")

pkg_check_modules(OASIS3PSMILE REQUIRED IMPORTED_TARGET "oasis3-psmile.MPI1")
include_directories(${OASIS3PSMILE_INCLUDE_DIRS})
message("OASIS3PSMILE_INCLUDEDIR: " ${OASIS3PSMILE_INCLUDEDIR})
message("OASIS3PSMILE_INCLUDE_DIRS: " ${OASIS3PSMILE_INCLUDE_DIRS})

pkg_check_modules(OASIS3SCRIP REQUIRED IMPORTED_TARGET "oasis3-scrip")
include_directories(${OASIS3SCRIP_INCLUDE_DIRS})
message("OASIS3SCRIP_INCLUDEDIR: " ${OASIS3SCRIP_INCLUDEDIR})
message("OASIS3SCRIP_INCLUDE_DIRS: " ${OASIS3SCRIP_INCLUDE_DIRS})


# libutil.a library
file(GLOB LIBUTIL_SOURCES libutil/src/*.F90)
add_library(util ${LIBUTIL_SOURCES})

# libforcing.a library
file(GLOB LIBFORCING_SOURCES libforcing/src/*.F90)
add_library(forcing ${LIBFORCING_SOURCES})
add_dependencies(forcing util PkgConfig::JSONFORTRAN PkgConfig::DATETIME)

# libcouple.a library
file(GLOB LIBCOUPLE_SOURCES libcouple/src/*.F90)
add_library(couple ${LIBCOUPLE_SOURCES})
add_dependencies(couple forcing util PkgConfig::DATETIME PkgConfig::OASIS3PSMILE)

# Join all of the above together to make libaccesom2
# See https://stackoverflow.com/questions/37924383/combining-several-static-libraries-into-one-using-cmake
set(LIBACCESSOM2 ${CMAKE_BINARY_DIR}/lib/libaccessom2.a)

add_custom_target(combined
        COMMAND ar -x $<TARGET_FILE:util>
        COMMAND ar -x $<TARGET_FILE:forcing>
        COMMAND ar -x $<TARGET_FILE:couple>
        COMMAND ar -qcs ${LIBACCESSOM2} *.o
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        DEPENDS util forcing couple
        )

add_library(accessom2 STATIC IMPORTED GLOBAL)
add_dependencies(accessom2 combined)
set_target_properties(accessom2 PROPERTIES IMPORTED_LOCATION ${LIBACCESSOM2})

# libforcing test executable
file(GLOB FORCING_TEST_SOURCES libforcing/test/*.F90)
add_executable(forcing_test.exe ${FORCING_TEST_SOURCES})
target_link_libraries(forcing_test.exe forcing util PkgConfig::DATETIME PkgConfig::JSONFORTRAN PkgConfig::NETCDF)
set_target_properties(forcing_test.exe PROPERTIES
                      RUNTIME_OUTPUT_DIRECTORY libforcing/test/
)

# yatm executable
file(GLOB ATM_SOURCES atm/src/*.F90)
add_executable(yatm.exe ${ATM_SOURCES})
target_link_libraries(yatm.exe accessom2 PkgConfig::DATETIME PkgConfig::JSONFORTRAN PkgConfig::OASIS3PSMILE PkgConfig::OASIS3MCT PkgConfig::OASIS3MPEU PkgConfig::OASIS3SCRIP PkgConfig::NETCDF ${MPI_Fortran_LIBRARIES})

# ice stub executable
file(GLOB ICE_STUB_SOURCES ice_stub/src/*.F90)
add_executable(ice_stub.exe ${ICE_STUB_SOURCES})
target_link_libraries(ice_stub.exe accessom2 PkgConfig::DATETIME PkgConfig::OASIS3PSMILE PkgConfig::OASIS3MCT PkgConfig::OASIS3MPEU PkgConfig::OASIS3SCRIP PkgConfig::NETCDF ${MPI_Fortran_LIBRARIES})

# ocean stub executable
file(GLOB OCEAN_STUB_SOURCES ocean_stub/src/*.F90)
add_executable(ocean_stub.exe ${OCEAN_STUB_SOURCES})
target_link_libraries(ocean_stub.exe accessom2 PkgConfig::DATETIME PkgConfig::OASIS3PSMILE PkgConfig::OASIS3MCT PkgConfig::OASIS3MPEU PkgConfig::OASIS3SCRIP PkgConfig::NETCDF ${MPI_Fortran_LIBRARIES})

