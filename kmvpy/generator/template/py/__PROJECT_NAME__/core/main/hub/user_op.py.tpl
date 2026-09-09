import hashlib
import json
import re
from datetime import datetime

from kmvpy.common.exception.kmv_exception import KmvException

from __PROJECT_NAME__.common.exception import user_op_errors as user_op_exc


class UserOpHub:
    """用户账号Hub规则；不依赖 DTO、ORM、DB、Redis 或 Web 框架。"""

    DEBUG_EMAIL_CAPTCHA_CODE = "666666"
    EMAIL_CAPTCHA_TTL_SECONDS = 300
    EMAIL_CAPTCHA_KEY_PREFIX = "user_op:email_captcha"
    EMAIL_SCENES = {"register", "login"}
    EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    PHONE_PATTERN = re.compile(r"^1[3-9]\d{9}$")
    USERNAME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_]{0,63}$")

    ACCOUNT_KIND_EMAIL = "email"
    ACCOUNT_KIND_PHONE = "phone"
    ACCOUNT_KIND_USERNAME = "username"

    USER_DB_USER_TYPE = 0
    ADMIN_DB_USER_TYPE = 100
    REVIEWER_DB_USER_TYPE = 2

    @staticmethod
    def normalize_email(email: str) -> str:
        normalized_email = (email or "").strip().lower()
        if not UserOpHub.EMAIL_PATTERN.fullmatch(normalized_email):
            raise KmvException(error=user_op_exc.INVALID_EMAIL_ERROR)
        return normalized_email

    @staticmethod
    def normalize_phone_for_login(phone: str) -> str:
        normalized_phone = (phone or "").strip()
        if not UserOpHub.PHONE_PATTERN.fullmatch(normalized_phone):
            raise KmvException(error=user_op_exc.INVALID_PHONE_ERROR)
        return normalized_phone

    @staticmethod
    def classify_login_account(account: str) -> str | None:
        """
        识别登录账号类型：email / phone / username。

        判定规则（利用用户名必以字母开头的约束，三种类型无歧义）：
        1. 含 @ 且符合邮箱格式 -> email；含 @ 但格式非法 -> None；
        2. 符合手机号格式（1 开头 11 位数字）-> phone；
        3. 以字母开头且符合用户名格式 -> username；
        4. 其余输入 -> None。
        """
        normalized = (account or "").strip()
        if not normalized:
            return None
        if "@" in normalized:
            if UserOpHub.EMAIL_PATTERN.fullmatch(normalized):
                return UserOpHub.ACCOUNT_KIND_EMAIL
            return None
        if UserOpHub.PHONE_PATTERN.fullmatch(normalized):
            return UserOpHub.ACCOUNT_KIND_PHONE
        if UserOpHub.USERNAME_PATTERN.fullmatch(normalized):
            return UserOpHub.ACCOUNT_KIND_USERNAME
        return None

    @staticmethod
    def normalize_username_for_login(username: str) -> str:
        normalized = (username or "").strip().lower()
        if not normalized:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)
        return normalized

    @staticmethod
    def normalize_username_for_admin_create(username: str) -> str:
        normalized = (username or "").strip().lower()
        if not normalized:
            raise KmvException(error=user_op_exc.USER_CREATE_ERROR)
        return normalized

    @staticmethod
    def normalize_admin_account(account: str) -> str:
        normalized = (account or "").strip()
        if not normalized:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)
        return normalized

    @staticmethod
    def normalize_email_scene(scene: str) -> str:
        normalized_scene = (scene or "").strip().lower()
        if normalized_scene not in UserOpHub.EMAIL_SCENES:
            raise KmvException(error=user_op_exc.INVALID_SCENE_ERROR)
        return normalized_scene

    @staticmethod
    def generate_email_captcha() -> str:
        return UserOpHub.DEBUG_EMAIL_CAPTCHA_CODE

    @staticmethod
    def verify_email_captcha_code(verify_code: str) -> None:
        if (verify_code or "").strip() != UserOpHub.DEBUG_EMAIL_CAPTCHA_CODE:
            raise KmvException(error=user_op_exc.CAPTCHA_INVALID_ERROR)

    @staticmethod
    def build_password_hash(password: str, salt: str) -> str:
        return hashlib.sha256(f"{password}:{salt}".encode("utf-8")).hexdigest()

    @staticmethod
    def verify_password(password: str, salt: str, stored_password_hash: str) -> None:
        password_hash = UserOpHub.build_password_hash(password, salt)
        if password_hash != stored_password_hash:
            raise KmvException(error=user_op_exc.PASSWORD_INVALID_ERROR)

    @staticmethod
    def build_email_captcha_key(scene: str, email: str) -> str:
        return f"{UserOpHub.EMAIL_CAPTCHA_KEY_PREFIX}:{scene}:{email}"

    @staticmethod
    def parse_email_captcha_payload(payload: str) -> dict[str, str] | None:
        try:
            data = json.loads(payload)
        except json.JSONDecodeError:
            return None
        return data if isinstance(data, dict) else None

    @staticmethod
    def is_email_captcha_expired(expire_at_text: str | None) -> bool:
        if not expire_at_text:
            return True
        try:
            expire_at = datetime.fromisoformat(expire_at_text)
        except ValueError:
            return True
        return expire_at <= datetime.now()

    @staticmethod
    def normalize_invitation_code(invitation_code: str | None) -> str | None:
        normalized_invitation_code = (invitation_code or "").strip().upper()
        if not normalized_invitation_code:
            return None
        return normalized_invitation_code

    @staticmethod
    def default_nickname_from_email(email: str, nickname: str | None = None) -> str:
        return (nickname or email.split("@", 1)[0]).strip()[:32]

    @staticmethod
    def default_nickname_from_username(username: str) -> str:
        return username.strip()[:32]

    @staticmethod
    def normalize_optional_profile_value(value: str | None) -> str | None:
        if value is None:
            return None
        normalized_value = value.strip()
        return normalized_value or None

    @staticmethod
    def ensure_profile_update_has_changes(
        *,
        nickname: str | None,
        signature: str | None,
        phone: str | None,
    ) -> None:
        if nickname is None and signature is None and phone is None:
            raise KmvException(error=user_op_exc.EMPTY_USER_PROFILE_UPDATE_ERROR)

    @staticmethod
    def ensure_user_can_login_from_user_portal(user_type: int) -> None:
        if int(user_type) == UserOpHub.ADMIN_DB_USER_TYPE:
            raise KmvException(error=user_op_exc.ADMIN_USE_ADMIN_LOGIN_ERROR)

    @staticmethod
    def is_regular_user(user_type: int) -> bool:
        return int(user_type) == UserOpHub.USER_DB_USER_TYPE

    @staticmethod
    def ensure_admin_login_allowed(user_type: int) -> None:
        if int(user_type) != UserOpHub.ADMIN_DB_USER_TYPE:
            raise KmvException(error=user_op_exc.NOT_ADMIN_ERROR)

    @staticmethod
    def ensure_not_target_self(target_kid: str | int, current_admin_kid: int) -> None:
        if int(target_kid) == int(current_admin_kid):
            raise KmvException(error=user_op_exc.CANNOT_ACT_ON_SELF_ERROR)

    @staticmethod
    def ensure_target_user_available(*, exists: bool, is_deleted: bool) -> None:
        if not exists or is_deleted:
            raise KmvException(error=user_op_exc.TARGET_USER_NOT_FOUND_ERROR)

    @staticmethod
    def db_user_type_for_admin_create(literal: int) -> int:
        if literal == 1:
            return UserOpHub.ADMIN_DB_USER_TYPE
        if literal == 2:
            return UserOpHub.REVIEWER_DB_USER_TYPE
        return UserOpHub.USER_DB_USER_TYPE

    @staticmethod
    def should_revoke_sessions_after_state_update(state: int) -> bool:
        return int(state) != 1
