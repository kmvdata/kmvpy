import { postAdminApi } from "src/boot/axios_admin";
import type {
  AdminServiceRestartReq,
  AdminServiceRestartRes,
} from "src/network/dto/admin/system";

export class ApiAdminSystem {
  static restartService(
    requestData: AdminServiceRestartReq,
  ): Promise<AdminServiceRestartRes> {
    return postAdminApi<AdminServiceRestartReq, AdminServiceRestartRes>(
      "/api/admin/system/service/restart",
      requestData,
      "触发服务重启失败",
    );
  }
}
