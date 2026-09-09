from typing import Optional, Dict, Any, List

from pydantic import BaseModel, model_validator

from kmvpy.common.st.st_expect import StExpect


class NextStepRequest(BaseModel):
    request: Optional[Dict[str, Any]] = None

    def consume(self) -> Optional[Dict[str, Any]]:
        request = self.request
        self.request = None
        return dict(request) if request is not None else None


class Step(BaseModel):
    step_kid: str
    action: str
    comment: Optional[str] = None
    request: Optional[Dict[str, Any]] = None

    @model_validator(mode="before")
    @classmethod
    def _compat_request_fields(cls, values):
        if isinstance(values, dict):
            if "request" not in values and "inputs" in values:
                values["request"] = values.pop("inputs")
            if "step_kid" not in values and "kid" in values:
                values["step_kid"] = values.pop("kid")
        return values


class StTestCase(BaseModel):
    name: Optional[str] = None
    comment: Optional[str] = None
    username: Optional[str] = None
    steps: List[Step]
    expected: StExpect

    @model_validator(mode="before")
    @classmethod
    def _compat_case_comment(cls, values):
        if isinstance(values, dict) and "comment" not in values and "name" in values:
            values["comment"] = values["name"]
        return values

    @property
    def case_id(self) -> str:
        return self.comment or self.name or "unnamed-case"


"""
配置示例：

```yaml
test_email_login:
  comment: user login smoke
  case_list:
    - comment: login with registered account
      steps:
        - step_kid: STEP_SEND_VERIFY_CODE
          action: POST /api/user/email/verify-code
          request:
            email: smoke_login@example.com
            scene: register

        - step_kid: STEP_REGISTER_USER
          action: POST /api/user/email/register
          request:
            email: smoke_login@example.com
            verify_code: "666666"
            password: "SmokePass123"
            nickname: smoke-login

        - step_kid: STEP_EMAIL_LOGIN
          action: POST /api/user/email/login
          request:
            email: smoke_login@example.com
            password: "SmokePass123"

      expected:
        code: 0
        data:
          token_type: Bearer
          is_new_user: false
          user:
            email: smoke_login@example.com
            username: smoke_login@example.com
            nickname: smoke-login

"""
