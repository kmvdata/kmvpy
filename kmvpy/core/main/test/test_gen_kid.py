
class Base:
    """
    基础类
    """
    __name: str | None = None

    def call_name(self):
        print(f"{self.__class__}: {self.__name}")

    @classmethod
    def set_name(cls, name: str):
        """
        设置类名
        """
        cls.__name = name

class BaseA(Base):
    """
    基础类
    """
    def __init__(self):
        super().__init__()
        # 直接修改父类的私有属性，不调用set_name方法
        self._Base__name = "Baase AA"


class BaseB(Base):
    """
    基础类
    """
    pass



if __name__ == '__main__':
    base = Base()
    base_a = BaseA()
    base_b = BaseB()
    base.call_name()
    base_a.call_name()
    base_b.call_name()
    BaseA.set_name('Base New A')
    base.call_name()
    base_a.call_name()
    base_b.call_name()
    BaseB.set_name('Base New B')
    base.call_name()
    base_a.call_name()
    base_b.call_name()


