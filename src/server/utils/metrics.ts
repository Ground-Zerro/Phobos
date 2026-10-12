export function countPeers(
  clients: ReadonlyArray<{ enabled: boolean; latestHandshakeAt: Date | null }>
) {
  let enabled = 0;
  let connected = 0;
  for (const client of clients) {
    if (client.enabled) enabled++;
    if (isPeerConnected(client)) connected++;
  }
  return { configured: clients.length, enabled, connected };
}
