export default defineMetricsHandler('prometheus', async ({ event }) => {
  setHeader(event, 'Content-Type', 'text/plain');

  const wgInterface = await Database.interfaces.get();
  const clients = await WireGuard.getAllClients();
  const peers = countPeers(clients);
  const now = Date.now();
  const iface = `interface="${wgInterface.name}"`;

  const sent: string[] = [];
  const received: string[] = [];
  const handshakes: string[] = [];
  for (const client of clients) {
    const labels = `${iface},enabled="${client.enabled}",ipv4Address="${client.ipv4Address}",ipv6Address="${client.ipv6Address}",name="${client.name}"`;
    sent.push(`wireguard_sent_bytes{${labels}} ${client.transferTx ?? 0}`);
    received.push(
      `wireguard_received_bytes{${labels}} ${client.transferRx ?? 0}`
    );
    handshakes.push(
      `wireguard_latest_handshake_seconds{${labels}} ${client.latestHandshakeAt ? (now - client.latestHandshakeAt.getTime()) / 1000 : 0}`
    );
  }

  return [
    '# HELP wireguard_configured_peers',
    '# TYPE wireguard_configured_peers gauge',
    `wireguard_configured_peers{${iface}} ${peers.configured}`,
    '',
    '# HELP wireguard_enabled_peers',
    '# TYPE wireguard_enabled_peers gauge',
    `wireguard_enabled_peers{${iface}} ${peers.enabled}`,
    '',
    '# HELP wireguard_connected_peers',
    '# TYPE wireguard_connected_peers gauge',
    `wireguard_connected_peers{${iface}} ${peers.connected}`,
    '',
    '# HELP wireguard_sent_bytes Bytes sent to the peer',
    '# TYPE wireguard_sent_bytes counter',
    ...sent,
    '',
    '# HELP wireguard_received_bytes Bytes received from the peer',
    '# TYPE wireguard_received_bytes counter',
    ...received,
    '',
    '# HELP wireguard_latest_handshake_seconds UNIX timestamp seconds of the last handshake',
    '# TYPE wireguard_latest_handshake_seconds gauge',
    ...handshakes,
  ].join('\n');
});
