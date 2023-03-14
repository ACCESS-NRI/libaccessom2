
module ice_version_mod

! <OVERVIEW>
!   This module provides a string which is the version of the code
!   used to build this executable.
!
!   It can also be read from the command line with the following command:
!   $ strings <executable> | grep 'ICE_STUB_VERSION='
! </OVERVIEW>

implicit none
private

character (len=*), parameter, public :: ICE_STUB_VERSION = &
                                        "ICE_STUB_VERSION="//CMAKE_YATM_VERSION

contains

subroutine dummy_sub()
end subroutine dummy_sub

end module ice_version_mod
