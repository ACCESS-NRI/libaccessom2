#!/bin/bash

PROGNAME="$( basename ${BASH_SOURCE[0]} )"
PROJDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILDDIR="${PROJDIR}/build"

if hostname --fqdn | grep gadi.nci.org.au$ > /dev/null
then
	echo "${PROGNAME}: Set up environment on gadi.nci.org.au"
	module purge
	module load intel-compiler/2019.5.281
	module load netcdf/4.7.4
	module prepend-path PKG_CONFIG_PATH "${NETCDF_BASE}/lib/Intel/pkgconfig/"
	module load openmpi/4.0.2
fi

echo -e "${PROGNAME}: executing cmake with \$PATH set to: $PATH\n"

rm -rf ${BUILDDIR} && \
mkdir -p ${BUILDDIR} && \
cmake -S ${PROJDIR} -B ${BUILDDIR} && \
cmake --build ${BUILDDIR} --verbose
