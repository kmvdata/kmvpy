import json
from typing import Annotated, Union
from typing import Optional

from fastapi import Response
from pydantic import BaseModel

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.exception.kmv_error import KmvError
from kmvpy.common.tool.object_to_dict import object2dict


class PaginationDTO(BaseModel):
    page: Annotated[Union[int, None], '页码'] = 1
    size: Annotated[Union[int, None], '每页大小'] = 20


class ApiResponse(BaseModel):
    code: Annotated[int, '业务返回状态码'] = 0
    msg: Annotated[Optional[str], '业务返回说明'] = None    
    data: Annotated[Optional[object], '业务返回值'] = None
    page: Annotated[Optional[int], '页码'] = None
    size: Annotated[Optional[int], '每页大小'] = None
    total: Annotated[Optional[int], '业务返回总数量'] = None

    def __init__(self, code: int = 0, data: Optional[object] = None, msg: Optional[str] = None, total: Optional[int] = None, page: Optional[int] = None, size: Optional[int] = None):
        super().__init__()
        self.code = code
        self.data = data
        self.msg = msg
        self.total = total
        self.page = page
        self.size = size

    def is_succeed(self) -> bool:
        return self.code == 0

    @classmethod
    def success_response(cls, data: Optional[object] = None, msg: Optional[str] = None, total: Optional[int] = None, page: Optional[int] = None, size: Optional[int] = None,
                         ignores: Optional[set[str]] = None) -> Response:
        _response = cls(code=0, data=data, msg=msg, total=total, page=page, size=size)
        response = Response(content=json.dumps(object2dict(_response, ignores), ensure_ascii=False),
                            media_type="application/json")
        return response

    @classmethod
    def error_response(cls, e: Annotated[Exception, '系统抛出的异常']) -> Response:
        _response = cls()
        
        # 检测异常类型并相应处理
        if isinstance(e, KmvException):
            # KmvException 类型使用特定逻辑
            _response.code = e.error_code
            _response.msg = e.error_msg if e.error_more_msg is None else e.error_more_msg
        else:
            # 其他异常类型使用通用逻辑
            if hasattr(e, 'error_code'):
                _response.code = e.error_code
            else:
                _response.code = getattr(e, 'error_code', 10000)
            
            if hasattr(e, 'error_msg') and hasattr(e, 'error_more_msg'):
                _response.msg = e.error_msg if e.error_more_msg is None else e.error_more_msg
            else:
                _response.msg = str(e) or '未知异常'
        
        response = Response(content=json.dumps(object2dict(_response), ensure_ascii=False),
                            media_type="application/json")
        return response

    @staticmethod
    def unknown_error_response() -> Response:
        return ApiResponse.from_exception(KmvException(error=KmvError.UNKNOWN_ERROR))


class SocketioResponse(ApiResponse):

    @classmethod
    def success_response(cls, data: Optional[object] = None, total: Optional[int] = None, fields: str = None) -> str:
        _response = cls()
        _response.code = 0
        _response.msg = ''
        _response.total = total
        _response.data = data
        response = Response(content=json.dumps(object2dict(_response), ensure_ascii=False),
                            media_type="application/json")
        return response.body.decode()

    @classmethod
    def error_response(cls, e: Annotated[Exception, '系统抛出的异常']) -> str:
        _response = cls()
        
        # 检测异常类型并相应处理
        if isinstance(e, KmvException):
            # KmvException 类型使用特定逻辑
            _response.code = e.error_code
            _response.msg = e.error_msg if e.error_more_msg is None else e.error_more_msg
        else:
            # 其他异常类型使用通用逻辑
            if hasattr(e, 'error_code'):
                _response.code = e.error_code
            else:
                _response.code = getattr(e, 'error_code', 10000)
            
            if hasattr(e, 'error_msg') and hasattr(e, 'error_more_msg'):
                _response.msg = e.error_msg if e.error_more_msg is None else e.error_more_msg
            else:
                _response.msg = str(e) or '未知异常'
        
        response = Response(content=json.dumps(object2dict(_response), ensure_ascii=False),
                            media_type="application/json")
        return response.body.decode()

    @staticmethod
    def unknown_error_response() -> Response:
        return ApiResponse.from_exception(KmvException(error=KmvError.UNKNOWN_ERROR))
