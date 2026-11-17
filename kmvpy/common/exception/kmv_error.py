import i18n


class KmvError(object):
    """
    统一错误码定义。

    说明:
    错误码用来区分需要不同处理方法的异常，如果处理方法相同，建议用同一错误码，不同的个性化错误详细信息(数组的第三个元素)
    [0]给前端程序用来判断, [1]元素更多的是给内部开发者看, [2]更多给外部用户看
    """

    COMMON_CODE = 0
    CODE = COMMON_CODE + 10000

    SUCCESS = [0, "success", "success"]
    UNKNOWN_ERROR = [COMMON_CODE + 10000, "未知错误", ""]
    PARAMETER_ERROR = [COMMON_CODE + 10002, i18n.t("kmvpy.PARAMETER_ERROR"), "参数错误"]
    NOT_FOUND_ERROR = [COMMON_CODE + 10003, i18n.t("kmvpy.NOT_FOUNT_ERROR"), "资源不存在"]

    CORE_ERROR = [COMMON_CODE + 20000, "core错误", ""]
    ADMIN_ERROR = [COMMON_CODE + 20001, "admin错误", ""]
    SESSION_ERROR = [COMMON_CODE + 20002, "session错误", ""]
    ACCOUNT_ASSET_CHANGE_ERROR = [COMMON_CODE + 20013, "账户资产变更错误", ""]
    SIGNUP_ERROR = [COMMON_CODE + 20014, "注册失败", ""]

    NO_AUTH = [COMMON_CODE + 100, "没有权限", ""]
    NOT_SIGNIN_ADMIN = [COMMON_CODE + 101, "需要登录", ""]
    ADMIN_SIGNIN_ERROR = [COMMON_CODE + 102, "管理员登录错误", ""]
    DELETE_GROUP_ERROR = [COMMON_CODE + 207, "删除组失败", ""]
    NO_GROUP = [COMMON_CODE + 208, "找不到组", ""]
    AUTH_ERROR = [COMMON_CODE + 209, "权限错误", ""]
    GROUP_ERROR = [COMMON_CODE + 210, "组错误", ""]

    PRETRAINED_MODEL_ERROR = [CODE + 1, "预训练模型错误", ""]

    NOT_SIGNIN = [CODE + 206, "未登录", ""]
    SIGNIN_ERROR = [CODE + 213, "登录失败", ""]

    PAY_ERROR = [CODE + 1004, "支付失败", ""]
    NO_TOKEN = [CODE + 1005, "没有token", ""]
    INFERENCE_ERROR = [CODE + 1006, "推理错误", ""]

    CAPTCHA_ERROR = [CODE + 4000, "发送验证码错误", ""]
