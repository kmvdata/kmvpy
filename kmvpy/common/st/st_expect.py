from typing import Any, List, NamedTuple, Optional

from pydantic import BaseModel, model_validator

from kmvpy.common.response import ApiResponse


class Mismatch(NamedTuple):
    """A single field mismatch: where it happened, what was expected, what was found."""
    path: str
    expected: Any
    actual: Any


class StExpect(BaseModel):
    """
    预设的期望值。
    与ApiResponse格式呼应，实现必要条件判断：
    ApiResponse成立 → StExpect必然成立
    """
    code: int = 0
    msg: Optional[str] = None
    data: Optional[dict] = None
    total: Optional[int] = None

    @model_validator(mode='before')
    @classmethod
    def _compat_count(cls, values):
        """兼容旧字段名 count，自动映射到 total"""
        if isinstance(values, dict) and 'count' in values and 'total' not in values:
            values['total'] = values.pop('count')
        return values

    def check(self, resp: ApiResponse) -> List[Mismatch]:
        """
        将 self 与 resp 逐字段对比，返回所有不匹配项。
        空列表表示全部必要条件均满足。
        """
        mismatches: List[Mismatch] = []
        if self.code is not None and self.code != resp.code:
            mismatches.append(Mismatch("code", self.code, resp.code))
        if self.msg is not None and self.msg != resp.msg:
            mismatches.append(Mismatch("msg", self.msg, resp.msg))
        if self.total is not None and self.total != resp.total:
            mismatches.append(Mismatch("total", self.total, resp.total))
        if self.data is not None:
            _collect_mismatches(self.data, resp.data, "data", mismatches)
        return mismatches

    def assert_on(self, resp: ApiResponse) -> None:
        """断言 resp 满足所有必要条件，失败时抛出带路径诊断的 AssertionError。"""
        mismatches = self.check(resp)
        if mismatches:
            lines = ["Smoke test assertion failed:"]
            for m in mismatches:
                lines.append(f"  {m.path}: expected {m.expected!r}, got {m.actual!r}")
            raise AssertionError("\n".join(lines))

    def is_required_condition_for(self, resp: ApiResponse) -> bool:
        """向后兼容的布尔判断接口。"""
        return len(self.check(resp)) == 0


def _collect_mismatches(expect: Any, actual: Any, path: str, out: List[Mismatch]) -> None:
    """递归收集 expect 与 actual 之间的不匹配项。"""
    if isinstance(expect, dict):
        if not isinstance(actual, dict):
            out.append(Mismatch(path, expect, actual))
            return
        for k, v in expect.items():
            child = f"{path}.{k}"
            if k not in actual:
                out.append(Mismatch(child, v, "<missing>"))
            else:
                _collect_mismatches(v, actual[k], child, out)
        return

    if isinstance(expect, list):
        if not isinstance(actual, list):
            out.append(Mismatch(path, expect, actual))
            return
        if len(expect) != len(actual):
            out.append(Mismatch(f"{path}.length", len(expect), len(actual)))
            return
        for i, (e, a) in enumerate(zip(expect, actual)):
            _collect_mismatches(e, a, f"{path}[{i}]", out)
        return

    if isinstance(expect, StExpect):
        if isinstance(actual, ApiResponse):
            for m in expect.check(actual):
                out.append(Mismatch(f"{path}.{m.path}", m.expected, m.actual))
        else:
            out.append(Mismatch(path, repr(expect), repr(actual)))
        return

    if expect != actual:
        out.append(Mismatch(path, expect, actual))
