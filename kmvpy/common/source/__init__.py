from typing import Annotated


class DataSource(object):
    browser: Annotated[any, "浏览器"] = None
    url: Annotated[str, "数据源首页"] = None
    domain: Annotated[str, "数据源域名，一般用于mongo的collection名"] = None
    path: Annotated[str, "数据根目录"] = None

    @classmethod
    def init_browser(cls) -> None:
        """
        初始化浏览器
        """
        pass

    @classmethod
    def index(cls) -> None:
        """
        访问首页
        """
        pass

    @classmethod
    def login(cls,
              wait: Annotated[int, "登录等待时间"] = 0,
              cookie_path: Annotated[str, "cookie保存路径"] = None) -> None:
        """
        登录
        """
        pass

    @classmethod
    def search(cls,
               current_page: Annotated[any, "当前页"],
               keyword: Annotated[str, "搜索关键字"],
               input_xpath: Annotated[str, "搜索框xpath"] = None,
               wait: Annotated[int, "等待搜索结果时间"] = 3,
               save_html: Annotated[bool, "是否保存html"] = False) -> None:
        """
        搜索
        """
        pass

    @classmethod
    def _click(cls,
               current_page: Annotated[any, "当前页"],
               click_item: Annotated[any, '点击元素'],
               open_new_window: Annotated[bool, "是否在新窗口打开"] = False) -> None:
        """
        增加了着色的点击的替代
        """


