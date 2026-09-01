export interface VoiceDescriptionSignal {
  kind: "description";
  description: {
    type: "offer" | "answer";
    sdp: string;
  };
}

export interface VoiceCandidateSignal {
  kind: "candidate";
  candidate: {
    candidate: string;
    sdpMid?: string | null;
    sdpMLineIndex?: number | null;
    usernameFragment?: string | null;
  } | null;
}

export type VoiceSignal = VoiceDescriptionSignal | VoiceCandidateSignal;

const MAX_SDP_LENGTH = 64 * 1024;
const MAX_CANDIDATE_LENGTH = 4096;
const MAX_ICE_FIELD_LENGTH = 256;

function optionalShortString(value: unknown): value is string | null | undefined {
  return value === undefined || value === null ||
    (typeof value === "string" && value.length <= MAX_ICE_FIELD_LENGTH);
}

export function validVoicePeerId(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9-]{8,128}$/.test(value);
}

export function validVoiceSignal(value: unknown): value is VoiceSignal {
  if (!value || typeof value !== "object" || !("kind" in value)) return false;

  if (value.kind === "description") {
    if (!("description" in value) || !value.description || typeof value.description !== "object") {
      return false;
    }
    const description = value.description as Record<string, unknown>;
    return (description.type === "offer" || description.type === "answer") &&
      typeof description.sdp === "string" &&
      description.sdp.length > 0 &&
      description.sdp.length <= MAX_SDP_LENGTH;
  }

  if (value.kind === "candidate") {
    if (!("candidate" in value)) return false;
    if (value.candidate === null) return true;
    if (!value.candidate || typeof value.candidate !== "object") return false;
    const candidate = value.candidate as Record<string, unknown>;
    return typeof candidate.candidate === "string" &&
      candidate.candidate.length <= MAX_CANDIDATE_LENGTH &&
      optionalShortString(candidate.sdpMid) &&
      (candidate.sdpMLineIndex === undefined || candidate.sdpMLineIndex === null ||
        (Number.isInteger(candidate.sdpMLineIndex) &&
          Number(candidate.sdpMLineIndex) >= 0 && Number(candidate.sdpMLineIndex) <= 255)) &&
      optionalShortString(candidate.usernameFragment);
  }

  return false;
}
