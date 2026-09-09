from __PROJECT_NAME__.core.main.router.user.user_op import router as user_op_router
from __PROJECT_NAME__.core.main.router.user.work_ticket import router as user_work_ticket_router
from __PROJECT_NAME__.core.main.router.user.socket import router as user_socket_router
from __PROJECT_NAME__.core.main.router.admin.admin_op import router as admin_op_router
from __PROJECT_NAME__.core.main.router.admin.socket import router as admin_socket_router
from __PROJECT_NAME__.core.main.router.admin.database_table import router as admin_database_table_router
from __PROJECT_NAME__.core.main.router.admin.system import router as admin_system_router
from __PROJECT_NAME__.core.main.router.admin.work_ticket import router as admin_work_ticket_router

routers = [
    user_op_router,
    user_work_ticket_router,
    user_socket_router,
    admin_op_router,
    admin_socket_router,
    admin_database_table_router,
    admin_system_router,
    admin_work_ticket_router,
]
