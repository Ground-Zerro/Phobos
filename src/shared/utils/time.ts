export function isPeerConnected(client: { latestHandshakeAt: Date | null }) {
  if (!client.latestHandshakeAt) {
    return false;
  }

  const lastHandshakeMs = Date.now() - client.latestHandshakeAt.getTime();

  return lastHandshakeMs < PEER_ONLINE_WINDOW_MS;
}

export const PEER_ONLINE_WINDOW_MS = 1000 * 60 * 3;
