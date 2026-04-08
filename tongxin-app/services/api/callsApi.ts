import messagesClient from './messagesClient';

export interface CallRecord {
  id: string;
  conversation_id: string;
  initiator_id: string;
  room_name: string;
  call_type: string;
  status: 'ringing' | 'active' | 'rejected' | 'ended';
  started_at: string;
  answered_at?: string;
  ended_at?: string;
  ended_by?: string;
  end_reason?: string;
  created_at: string;
  updated_at: string;
}

export interface LiveKitTokenPayload {
  server_url: string;
  room_name: string;
  token: string;
  identity: string;
}

export async function startCall(conversationId: string, callType = 'voice'): Promise<CallRecord> {
  const { data } = await messagesClient.post('/api/calls/start', {
    conversation_id: conversationId,
    call_type: callType,
  });
  return data;
}

export async function getCall(callId: string): Promise<CallRecord> {
  const { data } = await messagesClient.get(`/api/calls/${callId}`);
  return data;
}

export async function getLiveKitToken(callId: string): Promise<LiveKitTokenPayload> {
  const { data } = await messagesClient.get(`/api/calls/${callId}/livekit-token`);
  return data;
}

export async function acceptCall(callId: string): Promise<CallRecord> {
  const { data } = await messagesClient.post(`/api/calls/${callId}/accept`);
  return data;
}

export async function rejectCall(callId: string, reason?: string): Promise<CallRecord> {
  const { data } = await messagesClient.post(`/api/calls/${callId}/reject`, { reason });
  return data;
}

export async function endCall(callId: string, reason?: string): Promise<CallRecord> {
  const { data } = await messagesClient.post(`/api/calls/${callId}/end`, { reason });
  return data;
}
