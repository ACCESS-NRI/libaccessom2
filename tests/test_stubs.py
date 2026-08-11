
import os
import f90nml
import json
import ast
import pytest
import datetime
import netCDF4 as nc
import numpy as np
import dateutil.parser
import shutil
from collections import OrderedDict
from helper import Helper

def dicts_to_list(key_name, log_str):
    lines = filter(lambda x : key_name in x, log_str.splitlines())
    out = []
    for l in lines:
        out += list(ast.literal_eval(l.strip()).values())
    return out


def get_exchange_datetimes(log_str):
    """
    Return the (cur_exp_dts, cur_forcing_dts) pairs logged once per exchange.
    """

    cur_exp_dts = dicts_to_list('cur_exp-datetime', log_str)
    cur_exp_dts = [dateutil.parser.parse(d) for d in cur_exp_dts]
    cur_forcing_dts = dicts_to_list('cur_forcing-datetime', log_str)
    cur_forcing_dts = [dateutil.parser.parse(d) for d in cur_forcing_dts]
    assert len(cur_exp_dts) == len(cur_forcing_dts) > 0

    return cur_exp_dts, cur_forcing_dts

@pytest.fixture
def helper():
    return Helper()

@pytest.fixture(params=['JRA55_RYF_MINIMAL', 'JRA55_IAF', 'JRA55_RYF', 'JRA55_v1p4_IAF'])
def exp(request):
    yield request.param

@pytest.fixture(params=['JRA55_IAF_SINGLE_FIELD'])
def exp_fast(request):
    yield request.param


class TestStubs:

    @pytest.mark.fast
    def test_run(self, helper, exp):
        """
        Check that the default configurations run.
        """

        ret, output, log, matm_log = helper.run_exp(exp)
        assert ret == 0


    @pytest.mark.debugging
    def test_unchanged_forcing_checksums(self, helper, exp):
        """
        Test that checksums have not changed.
        """

        ret, output, log, matm_log = helper.run_exp(exp)
        assert ret == 0

        run_checksums = helper.filter_checksums(log)
        stored_checksums = helper.checksums(exp)

        # Check that keys are the same
        assert set(run_checksums.keys()) == set(stored_checksums.keys())
        # Check that everything is the same
        assert run_checksums == stored_checksums


    def test_forcing_perturbations(self, helper):
        """
        Test forcing field pertubation feature of libaccessom2.
        """

        forcing_field = None
        scaling_file = 'test_data/scaling.RYF.rsds.1990_1991.nc'
        forcing_file = '/g/data/ua8/JRA55-do/RYF/v1-3/RYF.rsds.1990_1991.nc'
        shutil.copy(forcing_file, scaling_file)

        keys = ['checksum-matmxx-swfld_ai-0000000000',
                'checksum-matmxx-swfld_ai-0000010800',
                'checksum-matmxx-swfld_ai-0000021600',
                'checksum-matmxx-swfld_ai-0000032400']

        with nc.Dataset(scaling_file, 'r+') as f:
            f.variables['rsds'][:] = 1.0
            for i in range(len(keys)):
                f.variables['rsds'][i] = i

        with nc.Dataset(forcing_file) as f:
            forcing_field = f.variables['rsds'][:len(keys), :]

        ret, output, log, matm_log = helper.run_exp('FORCING_SCALING_AND_OFFSET')
        assert ret == 0
        run_checksums = helper.filter_checksums(log)

        # Scaling multiplied by 0, 1, 2, 3
        for mult, k in enumerate(keys):
            expected_val = np.sum(forcing_field[mult, :]*mult + 5)
            assert abs(run_checksums[k] - (expected_val)) < (expected_val * 1e-7)


    @pytest.mark.slow
    def test_forcing_fields(self, helper, exp):
        """
        Check that dates and checksums from YATM match those calculated here
        """

        ret, output, log, matm_log = helper.run_exp(exp)
        assert ret == 0

        cur_exp_dts, cur_forcing_dts = get_exchange_datetimes(matm_log)

        # Get the experiment start and end dates
        exp_dir = os.path.join(helper.test_dir, exp)
        accessom2_config = os.path.join(exp_dir, 'accessom2.nml')
        with open(accessom2_config) as f:
            nml = f90nml.read(f)
            forcing_start_date = nml['date_manager_nml']['forcing_start_date']
            forcing_end_date = nml['date_manager_nml']['forcing_end_date']
            forcing_start_date = dateutil.parser.parse(forcing_start_date)
            forcing_end_date = dateutil.parser.parse(forcing_end_date)

        # Parse forcing.json
        forcing_config = os.path.join(exp_dir, 'forcing.json')
        with open(forcing_config) as f:
            forcing = json.load(f)

        # Check that first forcing time corrosponds to forcing_start_date
        assert cur_forcing_dts[0] == forcing_start_date

        # Check that field dt is all the same and as expected
        uniq_dt = list(OrderedDict.fromkeys(cur_forcing_dts))
        dt = [b - a for a, b in zip(uniq_dt, uniq_dt[1:])]
        assert set(dt).pop() == datetime.timedelta(hours=3)

        # Check that indices for a particular year are sequential and increasing

        # Check that we have the right numbers of duplicate indices, i.e. all
        # forcing fields have the same indices except for runoff

        # Check that indices go back to 0 when crossing a year boundary

        # Iterate over forcing in Python, check that Fortran code did the same
        # by comparing the checksums of each field.


    def test_restart(self, helper, exp):
        """
        Test that model restarts at the correct date.
        """
        pass

    @pytest.mark.slow
    def test_iaf_cycles(self, helper, exp_fast):
        """
        Test that experiment and forcing dates are always in sync.

        Esp relevant for multi-cycle IAF run, see:
        https://github.com/COSIMA/access-om2/issues/149
        """

        cycle_length = 5
        runtime_years = 5*cycle_length
        # replay_years is the list of experiment years where the forcing year is not a leap year
        # but the experiment year is. accessom2_progress_date replays the previous forcing for
        # the leap day in these years.
        replay_years = [1964, 1968, 1972, 1976]
        curr_year = 0

        while curr_year <= runtime_years:
            restart = curr_year != 0
            ret, output, log, matm_log = helper.run_exp(exp_fast, restart=restart, years_duration=1)
            assert ret == 0

            curr_cycle = curr_year // cycle_length

            cur_exp_dts, cur_forcing_dts = get_exchange_datetimes(matm_log)

            for exp_dt, forcing_dt in zip(cur_exp_dts, cur_forcing_dts):
                # Check the experiment year
                assert exp_dt.year == curr_year + 1958
                assert exp_dt.year == forcing_dt.year + (curr_cycle * cycle_length)

                if exp_dt.year in replay_years and exp_dt.month == 2 and exp_dt.day == 29:
                    # The forcing year doesn't have this leap day, so the
                    # previous forcing day is replayed instead.
                    assert forcing_dt.month == 2 and forcing_dt.day == 28
                else:
                    # Check that experiment and forcing dates only differ in the year.
                    assert exp_dt.month == forcing_dt.month
                    assert exp_dt.day == forcing_dt.day

                assert exp_dt.hour == forcing_dt.hour
                assert exp_dt.minute == forcing_dt.minute
                assert exp_dt.second == forcing_dt.second

            curr_year += 1
