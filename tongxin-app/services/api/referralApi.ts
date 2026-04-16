import apiClient from './client';

// ── Types ──
export interface ReferralOverview {
  my_rebate_rate: number;
  lifetime_commission_earned: number;
  this_month_commission: number;
  invite_count: number;
  is_agent: boolean;
  invite_code: string;
  invite_link: string;
}

export interface CommissionRecord {
  id: string;
  inviter_uid: string;
  period_date: string;
  kind: string; // 'direct' | 'override'
  settled_amount: number;
  event_count: number;
  status: string;
  created_at: string;
}

export interface Invitee {
  uid: string;
  display_name: string;
  avatar_url: string;
  registered_at: string;
  total_fee_contributed: number;
}

export interface InviteLink {
  id: string;
  owner_uid: string;
  code: string;
  landing_page: string;
  name: string;
  is_active: boolean;
  registration_count: number;
  created_at: string;
}

export interface SubAgentRow {
  uid: string;
  display_name: string;
  avatar_url: string;
  my_rebate_rate: number;
  this_month_volume: number;
  contrib_to_parent: number;
  is_frozen_referral: boolean;
}

export interface AgentDashboard {
  my_rebate_rate: number;
  lifetime_commission_earned: number;
  this_month_commission: number;
  this_month_override: number;
  sub_agent_count: number;
  total_invitees: number;
}

export interface AgentApplication {
  id: string;
  applicant_uid: string;
  status: string;
  channel_description: string;
  audience_size: string;
  contact_info: any;
  proposed_rate: number;
  created_at: string;
}

// ── User-facing referral APIs ──
export const referralApi = {
  getOverview: () =>
    apiClient.get<ReferralOverview>('/api/referral/me').then(r => r.data),

  listCommissionRecords: (kind?: string, limit = 20, offset = 0) =>
    apiClient.get<{ records: CommissionRecord[]; total: number }>('/api/referral/commission-records', {
      params: { kind, limit, offset },
    }).then(r => r.data),

  listInvitees: (limit = 20, offset = 0) =>
    apiClient.get<{ invitees: Invitee[]; total: number }>('/api/referral/invitees', {
      params: { limit, offset },
    }).then(r => r.data),

  validateCode: (code: string) =>
    apiClient.get<{ valid: boolean; owner_name: string }>('/api/referral/validate-code', {
      params: { code },
    }).then(r => r.data),
};

// ── Agent-facing APIs ──
export const agentApi = {
  apply: (data: { channel_description: string; audience_size: string; contact_info?: any }) =>
    apiClient.post('/api/agent/apply', data).then(r => r.data),

  getApplicationStatus: () =>
    apiClient.get<AgentApplication>('/api/agent/application-status').then(r => r.data),

  getDashboard: () =>
    apiClient.get<AgentDashboard>('/api/agent/dashboard-summary').then(r => r.data),

  listInviteLinks: () =>
    apiClient.get<InviteLink[]>('/api/agent/invite-links').then(r => r.data),

  createInviteLink: (data: { code: string; name: string; landing_page?: string }) =>
    apiClient.post<InviteLink>('/api/agent/invite-links', data).then(r => r.data),

  disableInviteLink: (id: string) =>
    apiClient.delete(`/api/agent/invite-links/${id}`).then(r => r.data),

  listSubAgents: () =>
    apiClient.get<SubAgentRow[]>('/api/agent/sub-agents').then(r => r.data),

  promoteSubAgent: (uid: string, rate: number) =>
    apiClient.post(`/api/agent/sub-agents/${uid}/promote`, { rate }).then(r => r.data),

  setSubAgentRate: (uid: string, rate: number) =>
    apiClient.put(`/api/agent/sub-agents/${uid}/rate`, { rate }).then(r => r.data),
};
