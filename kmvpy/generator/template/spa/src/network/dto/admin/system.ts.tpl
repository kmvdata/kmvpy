export interface AdminServiceRestartReq {
  confirm_text: string;
}

export interface AdminServiceRestartRes {
  accepted: boolean;
  restart_pid: number | null;
}
