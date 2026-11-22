import inspect
import os
from typing import Any, Dict, List, Optional

import pytest
import yaml

from kmvpy.common.st.st_expect import StExpect
from kmvpy.common.st.st_test_case import NextStepRequest, Step, StTestCase


class StBasePyTest:
    _config_cache: Dict[str, Dict] = {}
    _QUERYSTRING_METHODS = {"DELETE", "GET", "HEAD", "OPTIONS"}

    @classmethod
    def _load_config(cls, caller_src_path: str) -> Dict:
        """带缓存的配置加载"""
        if caller_src_path not in cls._config_cache:
            script_name = os.path.splitext(os.path.basename(caller_src_path))[0]
            config_path = os.path.join(os.path.dirname(caller_src_path), f"{script_name}.yaml")

            with open(config_path, "r", encoding="utf-8") as f:
                config = yaml.safe_load(f)
                config["user_map"] = {u["user_type"]: u for u in config.get("users", [])}

            cls._config_cache[caller_src_path] = config
        return cls._config_cache[caller_src_path]

    @classmethod
    def data_driven(cls, method: callable):
        """自动化参数化装饰器，通过被装饰方法的源文件定位同名 YAML。"""
        caller_path = os.path.abspath(inspect.getfile(method))
        method_name = method.__name__
        testcases = cls.generate_testcases(method_name, caller_path)
        test_case_list: List[StTestCase] = []
        try:
            for testcase in testcases:
                test_case_list.append(StTestCase(**testcase))
        except Exception as e:
            raise ValueError(f"Test case argument error: {e}")
        return pytest.mark.parametrize(
            "testdata",
            test_case_list,
            ids=lambda d: d.case_id
        )(method)

    @classmethod
    def generate_testcases(cls, method_name: str, caller_path: str) -> List[Dict]:
        """从 YAML 中读取指定方法名对应的 case_list。"""
        config = cls._load_config(caller_path)
        case_list = config.get(method_name, {}).get('case_list', [])
        for case in case_list:
            if 'comment' not in case and 'name' not in case:
                case['comment'] = (
                    config.get(method_name, {}).get('comment')
                    or config.get(method_name, {}).get('name')
                    or method_name
                )
        return list(case_list)

    # --- Step 执行框架 ---

    def run_case(self, client, testdata: StTestCase) -> None:
        """遍历所有 steps 并对最终响应做断言。子类一般不需要覆盖。"""
        runtime: dict = {}
        next_step_request = NextStepRequest()
        resp = None
        for step in testdata.steps:
            resp = self.on_step(client, step, runtime, next_step_request)
        self.on_assert(resp, testdata.expected)

    def on_step(
        self,
        client,
        step: Step,
        runtime: dict,
        next_step_request: Optional[NextStepRequest] = None,
    ):
        """
        分派单个 step。默认约定 step.action 为 "<METHOD> <URI>"，
        例如 "GET /api/ping"、"POST /api/user/email/register"。
        返回值会作为下一个 step 或最终断言的 resp。
        """
        next_step_request = next_step_request or NextStepRequest()
        step = self._resolve_step_request(step, next_step_request)
        self.before_step(step.step_kid, step, runtime, next_step_request)
        method, uri = self.parse_step_action(step.action)
        request_kwargs = self.build_request_kwargs(method, uri, step, runtime)
        response = client.request(method, uri, **request_kwargs)
        self.after_step(response, method, uri, step, runtime)
        self.after_step_hook(step.step_kid, response, method, uri, step, runtime, next_step_request)
        return response

    @staticmethod
    def parse_step_action(action: str) -> tuple[str, str]:
        raw_action = (action or "").strip()
        if not raw_action:
            raise ValueError("Step action is required")

        parts = raw_action.split(maxsplit=1)
        if len(parts) != 2:
            raise ValueError(
                "Step action must be '<METHOD> <URI>', "
                f"got: {action!r}"
            )

        method = parts[0].upper()
        uri = parts[1].strip()

        if not method.isalpha():
            raise ValueError(f"Invalid HTTP method in step action: {action!r}")
        if not uri:
            raise ValueError(f"Step action URI is required: {action!r}")

        return method, uri

    def build_request_kwargs(
        self,
        method: str,
        uri: str,
        step: Step,
        runtime: dict,
    ) -> dict[str, Any]:
        request_kwargs: dict[str, Any] = {}
        request = step.request
        if request is None:
            return request_kwargs

        payload_key = "params" if method in self._QUERYSTRING_METHODS else "json"
        request_kwargs[payload_key] = request
        return request_kwargs

    def before_step(
        self,
        step_kid: str,
        step: Step,
        runtime: dict,
        next_step_request: NextStepRequest,
    ) -> None:
        """供子类在当前 step 执行前，为下一个 step 设置 request 覆盖值。"""
        return None

    def after_step(
        self,
        response,
        method: str,
        uri: str,
        step: Step,
        runtime: dict,
    ) -> None:
        """供子类在请求完成后提取 token 等运行时状态。"""
        return None

    def after_step_hook(
        self,
        step_kid: str,
        response,
        method: str,
        uri: str,
        step: Step,
        runtime: dict,
        next_step_request: NextStepRequest,
    ) -> None:
        """供子类在当前 step 执行后，为下一个 step 设置 request 覆盖值。"""
        return None

    def on_assert(self, resp, expected: StExpect) -> None:
        """
        对最终响应做断言。默认期望 resp 是 ApiResponse。
        如果 resp 是 HTTP Response 对象，子类应覆盖此方法先做转换。
        """
        assert resp is not None, "No steps produced a response"
        expected.assert_on(resp)

    @staticmethod
    def _resolve_step_request(step: Step, next_step_request: NextStepRequest) -> Step:
        override_request = next_step_request.consume()
        if override_request is None:
            return step

        merged_request = dict(step.request or {})
        merged_request.update(override_request)
        return step.model_copy(update={"request": merged_request})
