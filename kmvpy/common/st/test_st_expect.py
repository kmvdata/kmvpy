import pytest

from kmvpy.common.response import ApiResponse
from kmvpy.common.st.st_expect import Mismatch, StExpect


def test_is_required_condition_for():
    resp = ApiResponse()
    expect = StExpect()
    resp.code = 0
    resp.msg = '2'
    resp.data = {'a': 1, 'b': 2, 'c': {
        'a': 1,
        'b': 2,
        'c': [{
            'a': 1,
            'b': 2,
        }, {'b': 2}]
    }}
    expect.code = 0
    expect.msg = '2'
    expect.data = {'a': 1, 'c': {'a': 1, 'c': [{'a': 1}, {'b': 2}]}}
    assert expect.is_required_condition_for(resp)


def test_assert_on_success():
    resp = ApiResponse(code=0, msg='ok', data={'key': 'value'})
    expect = StExpect(code=0, data={'key': 'value'})
    expect.assert_on(resp)


def test_assert_on_reports_mismatch_path():
    resp = ApiResponse(code=0, data={'user': {'name': 'alice'}})
    expect = StExpect(code=0, data={'user': {'name': 'bob'}})
    with pytest.raises(AssertionError, match=r"data\.user\.name"):
        expect.assert_on(resp)


def test_check_returns_all_mismatches():
    resp = ApiResponse(code=1, msg='fail')
    expect = StExpect(code=0, msg='ok')
    mismatches = expect.check(resp)
    assert len(mismatches) == 2
    assert mismatches[0] == Mismatch("code", 0, 1)
    assert mismatches[1] == Mismatch("msg", "ok", "fail")


def test_check_missing_dict_key():
    resp = ApiResponse(code=0, data={'a': 1})
    expect = StExpect(code=0, data={'a': 1, 'b': 2})
    mismatches = expect.check(resp)
    assert len(mismatches) == 1
    assert mismatches[0].path == "data.b"


def test_check_list_length_mismatch():
    resp = ApiResponse(code=0, data={'items': [1, 2]})
    expect = StExpect(code=0, data={'items': [1, 2, 3]})
    mismatches = expect.check(resp)
    assert len(mismatches) == 1
    assert "length" in mismatches[0].path


def test_total_field():
    resp = ApiResponse(code=0, total=10)
    expect = StExpect(code=0, total=10)
    assert expect.is_required_condition_for(resp)
    expect_bad = StExpect(code=0, total=5)
    assert not expect_bad.is_required_condition_for(resp)


def test_count_alias_compat():
    expect = StExpect.model_validate({'code': 0, 'count': 5})
    assert expect.total == 5
