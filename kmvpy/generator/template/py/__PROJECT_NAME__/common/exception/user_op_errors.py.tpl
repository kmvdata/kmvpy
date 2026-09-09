"""用户账号 / 管理员账号相关业务的 KmvException 错误三元组（41xxx）。"""

INVALID_EMAIL_ERROR = [41001, "邮箱格式不正确", "请输入正确的邮箱地址"]
INVALID_SCENE_ERROR = [41002, "验证码场景不支持", "验证码场景不支持"]
CAPTCHA_INVALID_ERROR = [41003, "验证码错误或已失效", "验证码错误或已失效"]
EMAIL_REGISTERED_ERROR = [41004, "邮箱已注册", "该邮箱已注册，请直接登录"]
USER_NOT_FOUND_ERROR = [41005, "用户不存在", "该账号尚未注册"]
PASSWORD_INVALID_ERROR = [41006, "账号或密码错误", "账号或密码错误"]
INVITATION_CODE_INVALID_ERROR = [
    41007,
    "邀请码不存在",
    "邀请码不存在，请确认后重试",
]
AUTHORIZATION_INVALID_ERROR = [
    41008,
    "未登录或登录已失效",
    "请先登录后再试",
]
EMPTY_USER_PROFILE_UPDATE_ERROR = [
    41009,
    "未传入任何待修改字段",
    "请至少传入一个需要修改的字段",
]
CONTACT_DUPLICATED_ERROR = [
    41010,
    "联系方式已被占用",
    "该联系方式已被其他账号使用，请更换后重试",
]
NOT_ADMIN_ERROR = [41011, "非管理员账号", "请使用管理员账号登录"]
REVIEWER_CREATE_ERROR = [41012, "审核员创建失败", "审核员创建失败，请重试"]
USER_ROLE_UPDATE_ERROR = [41013, "用户角色更新失败", "用户角色更新失败，请重试"]
USER_STATE_UPDATE_ERROR = [41014, "用户状态更新失败", "用户状态更新失败，请重试"]
TARGET_USER_NOT_FOUND_ERROR = [41015, "目标用户不存在", "未找到对应的用户"]
ADMIN_USE_ADMIN_LOGIN_ERROR = [
    41016,
    "请使用管理端登录",
    "该账号为管理员，请使用管理端登录入口获取令牌，用户端令牌无法访问管理接口",
]
USER_CREATE_ERROR = [41017, "用户创建失败", "用户创建失败，请重试"]
USER_PASSWORD_RESET_ERROR = [41018, "密码重置失败", "密码重置失败，请重试"]
USER_DELETE_ERROR = [41019, "用户删除失败", "用户删除失败，请重试"]
CANNOT_ACT_ON_SELF_ERROR = [
    41020,
    "不能对当前账号操作",
    "不能对当前登录的管理员账号执行此操作",
]
USERNAME_TAKEN_ERROR = [41021, "用户名已存在", "该用户名已被占用"]
INVALID_PHONE_ERROR = [
    41022,
    "手机号格式不正确",
    "请输入正确的手机号",
]
ACCOUNT_TYPE_UNRECOGNIZED_ERROR = [
    41023,
    "账号格式无法识别",
    "请输入邮箱、手机号或字母开头的用户名",
]
