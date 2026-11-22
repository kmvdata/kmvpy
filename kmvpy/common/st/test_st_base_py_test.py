from kmvpy.common.st import StBasePyTest, Step, StTestCase
from kmvpy.common.st.st_expect import StExpect


class _DummyClient:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def request(self, method, uri, **kwargs):
        self.calls.append((method, uri, kwargs))
        return self.responses.pop(0)


class _TrackingPyTest(StBasePyTest):
    def __init__(self):
        self.before_calls = []
        self.after_calls = []
        self.asserted_response = None

    def before_step(self, step_kid: str, step: Step, runtime: dict, next_step_request) -> None:
        self.before_calls.append((step_kid, step.request))
        if step_kid == "STEP_REGISTER":
            next_step_request.request = {
                "password": "override-password",
                "remember_me": True,
            }

    def after_step(self, response, method: str, uri: str, step: Step, runtime: dict) -> None:
        runtime["last_step"] = {
            "response": response,
            "method": method,
            "uri": uri,
            "action": step.action,
            "step_kid": step.step_kid,
        }

    def after_step_hook(self, step_kid: str, response, method: str, uri: str, step: Step, runtime: dict,
                        next_step_request) -> None:
        self.after_calls.append((step_kid, step.request))
        if step_kid == "STEP_SEND_VERIFY_CODE":
            next_step_request.request = {
                "verify_code": "888888",
                "channel": "email",
            }

    def on_assert(self, resp, expected: StExpect) -> None:
        self.asserted_response = resp


def test_parse_step_action():
    method, uri = StBasePyTest.parse_step_action("post /api/demo")
    assert method == "POST"
    assert uri == "/api/demo"


def test_on_step_sends_json_for_post():
    response = object()
    client = _DummyClient([response])
    runtime = {}
    testcase = _TrackingPyTest()

    result = testcase.on_step(
        client,
        Step(step_kid="STEP_LOGIN", action="POST /api/user/login", request={"email": "demo@example.com"}),
        runtime,
    )

    assert result is response
    assert client.calls == [
        (
            "POST",
            "/api/user/login",
            {"json": {"email": "demo@example.com"}},
        )
    ]
    assert runtime["last_step"]["method"] == "POST"
    assert runtime["last_step"]["uri"] == "/api/user/login"
    assert runtime["last_step"]["step_kid"] == "STEP_LOGIN"


def test_on_step_sends_params_for_get():
    response = object()
    client = _DummyClient([response])
    runtime = {}

    StBasePyTest().on_step(
        client,
        Step(step_kid="STEP_PING", action="GET /api/ping", request={"verbose": True}),
        runtime,
    )

    assert client.calls == [
        (
            "GET",
            "/api/ping",
            {"params": {"verbose": True}},
        )
    ]


def test_run_case_hooks_can_override_next_step_request():
    responses = [object(), object(), object()]
    client = _DummyClient(responses)
    testcase = _TrackingPyTest()
    testdata = StTestCase(
        comment="user smoke",
        steps=[
            Step(
                step_kid="STEP_SEND_VERIFY_CODE",
                action="POST /api/user/email/verify-code",
                request={"email": "demo@example.com", "scene": "register"},
            ),
            Step(
                step_kid="STEP_REGISTER",
                action="POST /api/user/email/register",
                request={
                    "email": "demo@example.com",
                    "verify_code": "666666",
                    "nickname": "smoke-user",
                },
            ),
            Step(
                step_kid="STEP_LOGIN",
                action="POST /api/user/email/login",
                request={
                    "email": "demo@example.com",
                    "password": "original-password",
                },
            ),
        ],
        expected=StExpect(),
    )

    testcase.run_case(client, testdata)

    assert testcase.before_calls == [
        ("STEP_SEND_VERIFY_CODE", {"email": "demo@example.com", "scene": "register"}),
        (
            "STEP_REGISTER",
            {
                "email": "demo@example.com",
                "verify_code": "888888",
                "nickname": "smoke-user",
                "channel": "email",
            },
        ),
        (
            "STEP_LOGIN",
            {
                "email": "demo@example.com",
                "password": "override-password",
                "remember_me": True,
            },
        ),
    ]
    assert testcase.after_calls == testcase.before_calls
    assert client.calls == [
        (
            "POST",
            "/api/user/email/verify-code",
            {"json": {"email": "demo@example.com", "scene": "register"}},
        ),
        (
            "POST",
            "/api/user/email/register",
            {
                "json": {
                    "email": "demo@example.com",
                    "verify_code": "888888",
                    "nickname": "smoke-user",
                    "channel": "email",
                }
            },
        ),
        (
            "POST",
            "/api/user/email/login",
            {
                "json": {
                    "email": "demo@example.com",
                    "password": "override-password",
                    "remember_me": True,
                }
            },
        ),
    ]
    assert testcase.asserted_response is responses[-1]


def test_step_supports_legacy_inputs_field():
    step = Step.model_validate(
        {
            "step_kid": "STEP_LEGACY",
            "action": "POST /api/demo",
            "inputs": {"name": "legacy"},
        }
    )

    assert step.request == {"name": "legacy"}


def test_parse_step_action_requires_method_and_uri():
    try:
        StBasePyTest.parse_step_action("call_ping")
    except ValueError as exc:
        assert "<METHOD> <URI>" in str(exc)
    else:
        raise AssertionError("Expected ValueError for invalid step action")
