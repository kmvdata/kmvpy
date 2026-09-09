import { postAdminApi } from '../../../boot/axios_admin';
import type {
  AdminWorkTicketDetailReq,
  AdminWorkTicketDetailRes,
  AdminWorkTicketListReq,
  AdminWorkTicketListRes,
  AdminWorkTicketReplyReq,
  AdminWorkTicketUpdateStatusReq,
} from '../../dto/admin/work_ticket';

export const ADMIN_WORK_TICKET_DETAIL_API_URI = '/api/admin/work_ticket/detail';

export class ApiAdminWorkTicket {
  static list(requestData: AdminWorkTicketListReq): Promise<AdminWorkTicketListRes> {
    return postAdminApi<AdminWorkTicketListReq, AdminWorkTicketListRes>(
      '/api/admin/work_ticket/list',
      requestData,
      '获取工单列表失败',
    );
  }

  static detail(requestData: AdminWorkTicketDetailReq): Promise<AdminWorkTicketDetailRes> {
    return postAdminApi<AdminWorkTicketDetailReq, AdminWorkTicketDetailRes>(
      ADMIN_WORK_TICKET_DETAIL_API_URI,
      requestData,
      '获取工单详情失败',
    );
  }

  static reply(requestData: AdminWorkTicketReplyReq): Promise<AdminWorkTicketDetailRes> {
    return postAdminApi<AdminWorkTicketReplyReq, AdminWorkTicketDetailRes>(
      '/api/admin/work_ticket/reply',
      requestData,
      '回复工单失败',
    );
  }

  static updateStatus(
    requestData: AdminWorkTicketUpdateStatusReq,
  ): Promise<AdminWorkTicketDetailRes> {
    return postAdminApi<AdminWorkTicketUpdateStatusReq, AdminWorkTicketDetailRes>(
      '/api/admin/work_ticket/status/update',
      requestData,
      '更新工单状态失败',
    );
  }
}
