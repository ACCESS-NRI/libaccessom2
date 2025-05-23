program atm

    use mod_oasis, only : OASIS_IN, OASIS_OUT
    use forcing_config_mod, only : forcing_config_type => forcing_config
    use forcing_field_mod, only : forcing_field_type => forcing_field, FORCING_FIELD_DOMAIN_LAND
    use coupler_mod, only : coupler_type => coupler
    use error_handler, only : assert
    use ice_grid_proxy_mod, only : ice_grid_type => ice_grid_proxy
    use runoff_mod, only : runoff_type => runoff
    use accessom2_mod, only : accessom2_type => accessom2
    use simple_timer_mod, only : simple_timer_type => simple_timer
    use logger_mod, only : LOG_INFO, LOG_DEBUG
    use yatm_version_mod, only : YATM_VERSION

    implicit none

    integer, parameter :: MAX_FILE_NAME_LEN = 1024

    type(accessom2_type) :: accessom2
    type(coupler_type) :: coupler
    type(forcing_config_type) :: forcing_config
    type(ice_grid_type) :: ice_grid
    type(runoff_type) :: runoff
    type(forcing_field_type), dimension(:), allocatable :: forcing_fields
    integer, dimension(:), allocatable :: to_runoff_map
    ! Liquid (river) and solid (iceberg) runoff
    type(forcing_field_type), dimension(:), allocatable :: runoff_forcing_fields
    character(len=MAX_FILE_NAME_LEN) :: forcing_file, accessom2_config_dir
    character(len=9) :: calendar
    integer, dimension(2) :: ice_shape
    integer :: i, ri, err, tmp_unit
    logical :: file_exists
    integer :: num_atm_to_ice_fields, dt, cur_runtime_in_seconds
    integer :: num_land_fields

    type(simple_timer_type) :: field_read_timer, ice_wait_timer
    type(simple_timer_type) :: init_runoff_timer, remap_runoff_timer
    type(simple_timer_type) :: coupler_put_timer
    type(simple_timer_type) :: init_oasis_timer, init_model_timer
    type(simple_timer_type) :: parse_forcing_fields_timer

    namelist /atm_nml/ forcing_file, accessom2_config_dir

    print *, YATM_VERSION

    ! Read input namelist
    forcing_file = 'forcing.json'
    accessom2_config_dir = '../'
    inquire(file='atm.nml', exist=file_exists)
    call assert(file_exists, 'Input atm.nml does not exist.')
    open(newunit=tmp_unit, file='atm.nml')
    read(tmp_unit, nml=atm_nml)
    close(tmp_unit)

    ! Initialise model-level init, config and sync/tracking module
    call accessom2%init('matmxx', config_dir=trim(accessom2_config_dir))
    call accessom2%print_version_info()

    ! Initialise timers
    call field_read_timer%init('field_read', accessom2%logger, &
                               accessom2%simple_timers_enabled())
    call ice_wait_timer%init('ice_wait', accessom2%logger, &
                             accessom2%simple_timers_enabled())
    call init_runoff_timer%init('init_runoff', accessom2%logger, &
                                 accessom2%simple_timers_enabled())
    call remap_runoff_timer%init('remap_runoff', accessom2%logger, &
                                 accessom2%simple_timers_enabled())
    call coupler_put_timer%init('coupler_put', accessom2%logger, &
                                 accessom2%simple_timers_enabled())
    call init_model_timer%init('init_model', accessom2%logger, &
                                accessom2%simple_timers_enabled())
    call init_oasis_timer%init('init_oasis', accessom2%logger, &
                                accessom2%simple_timers_enabled())
    call parse_forcing_fields_timer%init('parse_forcing_fields', accessom2%logger, &
                                accessom2%simple_timers_enabled())
    call init_model_timer%start()

    ! Initialise forcing object, this reads config and
    ! tells us how man atm-to-ice fields there are.
    call forcing_config%init(forcing_file, accessom2%logger, &
                             num_atm_to_ice_fields)

    ! Initialise forcing fields, involves reading details of each from
    ! config file and from netcdf files on disk, and allocating
    ! necessary memory.
    allocate(forcing_fields(num_atm_to_ice_fields))
    call parse_forcing_fields_timer%start()
    call forcing_config%parse(forcing_fields, accessom2%get_cur_forcing_date(), &
                              num_land_fields, dt, calendar)
    call parse_forcing_fields_timer%stop()

    ! Create intermediate fields for runoff,
    ! these are a copy/variation of the forcing fields
    allocate(runoff_forcing_fields(num_land_fields))

    ! Initialise the coupler.
    call coupler%init_begin('matmxx', accessom2%logger, &
                            config_dir=trim(accessom2_config_dir))

    ! Tell libaccessom2 about any global configs/state
    call accessom2%set_calendar(calendar)
    call accessom2%set_atm_timestep(dt)
    call accessom2%set_cpl_field_counts(num_atm_to_ice_fields=num_atm_to_ice_fields)
    ! Synchronise accessom2 'state' (i.e. configuration) between all PEs of all models.
    call accessom2%sync_config(coupler)

    ! Initialise ice grid proxy and get information about it,
    ! this is needed for local remapping.
    call ice_grid%init(coupler%ice_root)
    call ice_grid%recv()
    ice_shape = ice_grid%get_shape()

    ! Initialise the runoff remapping object with ice grid information.
    call init_runoff_timer%start()
    call runoff%init(ice_grid)
    call init_runoff_timer%stop()

    ! Create a little map to go from atm_to_ice field indices to
    ! runoff field indices, simplifies the code below
    allocate(to_runoff_map(num_atm_to_ice_fields))
    ri = 1
    do i=1, num_atm_to_ice_fields
        if (forcing_fields(i)%domain == FORCING_FIELD_DOMAIN_LAND) then
            to_runoff_map(i) = ri
            ri = ri + 1
        else
            to_runoff_map(i) = 0
        endif
    enddo

    ! Initialise coupling fields, runoff fields need special treatment.
    do i=1, num_atm_to_ice_fields
        if (to_runoff_map(i) /= 0) then
            ri = to_runoff_map(i)
            runoff_forcing_fields(ri)%coupling_name = &
                forcing_fields(i)%coupling_name
            runoff_forcing_fields(ri)%domain = forcing_fields(i)%domain
            allocate(runoff_forcing_fields(ri)%data_array(ice_shape(1), ice_shape(2)))
            call coupler%init_field(runoff_forcing_fields(ri)%coupling_name, &
                                    OASIS_OUT, &
                                    runoff_forcing_fields(ri)%get_shape())
        else
            call coupler%init_field(forcing_fields(i)%coupling_name, &
                                    OASIS_OUT, &
                                    forcing_fields(i)%get_shape())
        endif
    enddo

    ! Finish coupler initialisation. Tell oasis how long the run is and the
    ! coupling timesteps. This call also does MCT routing table initialisation
    ! which can be slow.
    call init_oasis_timer%start()
    call coupler%init_end(accessom2%get_total_runtime_in_seconds(), &
                          accessom2%get_coupling_field_timesteps())
    call init_oasis_timer%stop()
    call init_model_timer%stop()

    do while (.not. accessom2%run_finished())

        cur_runtime_in_seconds = int(accessom2%get_cur_runtime_in_seconds())

        ! Send each forcing field
        do i=1, num_atm_to_ice_fields
            ri = to_runoff_map(i)

            if (mod(cur_runtime_in_seconds, forcing_fields(i)%dt) == 0) then
                call field_read_timer%start()
                call forcing_fields(i)%update(accessom2%get_cur_forcing_date(), &
                                              accessom2%get_cur_exp_date())
                call field_read_timer%stop()
                if (ri /= 0) then
                    call remap_runoff_timer%start()
                    call runoff%remap(forcing_fields(i)%data_array, &
                                      runoff_forcing_fields(ri)%data_array, ice_grid%mask)
                    call remap_runoff_timer%stop()
                endif
            endif

            call coupler_put_timer%start()
            if (ri /= 0) then
                call coupler%put(runoff_forcing_fields(ri)%coupling_name, &
                                 runoff_forcing_fields(ri)%data_array, &
                                 cur_runtime_in_seconds, err)
            else
                call coupler%put(forcing_fields(i)%coupling_name, &
                                 forcing_fields(i)%data_array, &
                                 cur_runtime_in_seconds, err)
            endif
            call coupler_put_timer%stop()
        enddo

        ! Block until we receive from ice. Ice will do a nonblocking send immediately
        ! after receiving the above fields. This prevents the atm from sending continuously.
        call ice_wait_timer%start()
        call accessom2%atm_ice_sync()
        call ice_wait_timer%stop()

        call accessom2%logger%write(LOG_INFO, '{ "cur_exp-datetime" :  "'//accessom2%get_cur_exp_date_str()//'" }')
        call accessom2%logger%write(LOG_INFO, '{ "cur_forcing-datetime" : "'//accessom2%get_cur_forcing_date_str()//'" }')
        call accessom2%logger%write(LOG_DEBUG, 'cur_runtime_in_seconds ', &
                                    int(accessom2%get_cur_runtime_in_seconds()))
        ! Print out current model speed in h/h
        !call accessom2%logger%write(LOG_INFO, '{ "modeltime_over_walltime_hour_per_hour" : "" ',

        call accessom2%progress_date(dt)
    enddo

    call field_read_timer%write_stats()
    call ice_wait_timer%write_stats()
    call init_runoff_timer%write_stats()
    call remap_runoff_timer%write_stats()
    call coupler_put_timer%write_stats()
    call init_oasis_timer%write_stats()
    call init_model_timer%write_stats()
    call parse_forcing_fields_timer%write_stats()

    call accessom2%logger%write(LOG_INFO, 'Run complete, calling deinit')

    call coupler%deinit()
    call accessom2%deinit(finalize=.true.)
    call forcing_config%deinit()

end program atm
