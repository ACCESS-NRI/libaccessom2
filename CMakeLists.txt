# https://cmake.org/cmake/help/v3.6/module/FindPkgConfig.html
# 3.11: add_library() doesn't require dummy source
# 3.12: target_link_libraries() supports OBJECT targets
cmake_minimum_required(VERSION 3.12 FATAL_ERROR)
project(yatm
	DESCRIPTION "libaccessom2 is a library that is linked into all of the ACCESS-OM2 component models, including YATM, CICE and MOM. libaccessom2 provides functionality used by all models as well as providing a interface to inter-model communication and synchronisation tasks."
	VERSION 2.0.202212
	LANGUAGES Fortran
)

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
# Back to using the upstream version as the the bug is apparently not
# reproducible since intel-compiler/2019.5.281 and intel-compiler/2020.0.166:
# https://github.com/wavebitscientific/datetime-fortran/issues/51
pkg_check_modules(DATETIME REQUIRED IMPORTED_TARGET "datetime-fortran")
pkg_check_modules(JSONFORTRAN REQUIRED IMPORTED_TARGET "json-fortran")
pkg_check_modules(OASIS3MCT REQUIRED IMPORTED_TARGET "oasis3-mct")
pkg_check_modules(OASIS3MPEU REQUIRED IMPORTED_TARGET "oasis3-mpeu")
pkg_check_modules(OASIS3PSMILE REQUIRED IMPORTED_TARGET "oasis3-psmile.MPI1")
pkg_check_modules(OASIS3SCRIP REQUIRED IMPORTED_TARGET "oasis3-scrip")

# Workaround for compiler error:
# f951: Fatal Error: Cannot delete temporary module file 'include/error_handler.mod0': No such file or directory
# e.g. https://github.com/Unidata/netcdf-fortran/issues/64
add_library(util STATIC OBJECT)
target_sources(util PRIVATE
		libutil/src/error_handler.F90
		libutil/src/logger.F90
		libutil/src/simple_timer.F90
		libutil/src/util.F90
)
target_link_libraries(util)

add_library(accessom2 STATIC)
target_sources(accessom2 PRIVATE
		libforcing/src/error_handler.F90
		libforcing/src/forcing_config.F90
		libforcing/src/forcing_field.F90
		libforcing/src/forcing_perturbation.F90
		libforcing/src/ncvar.F90
		libforcing/src/util.F90
		libcouple/src/accessom2.F90
		libcouple/src/coupler.F90
		libcouple/src/libaccessom2_version.F90
		libcouple/src/restart.F90
)
target_link_libraries(accessom2 util PkgConfig::OASIS3PSMILE)


# libforcing test executable
file(GLOB FORCING_TEST_SOURCES libforcing/test/*.F90)
add_executable(forcing_test.exe ${FORCING_TEST_SOURCES})
target_link_libraries(forcing_test.exe accessom2 PkgConfig::DATETIME PkgConfig::JSONFORTRAN PkgConfig::NETCDF)
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

configure_file(libaccessom2.pc.in lib/pkgconfig/libaccessom2.pc @ONLY)


install(TARGETS accessom2)
install(TARGETS yatm.exe)
install(TARGETS ice_stub.exe)
install(TARGETS ocean_stub.exe)
# Fortran mod files
install(DIRECTORY ${CMAKE_BINARY_DIR}/include/ TYPE INCLUDE)
install(FILES ${CMAKE_BINARY_DIR}/lib/pkgconfig/libaccessom2.pc DESTINATION lib/pkgconfig)

