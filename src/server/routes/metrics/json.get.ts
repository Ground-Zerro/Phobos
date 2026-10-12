export default defineMetricsHandler('json', async () => {
  const clients = await WireGuard.getAllClients();
  const peers = countPeers(clients);
  return {
    wireguard_configured_peers: peers.configured,
    wireguard_enabled_peers: peers.enabled,
    wireguard_connected_peers: peers.connected,
    clients: clients.map((client) => ({
      name: client.name,
      enabled: client.enabled,
      ipv4Address: client.ipv4Address,
      ipv6Address: client.ipv6Address,
      publicKey: client.publicKey,
      endpoint: client.endpoint,
      latestHandshakeAt: client.latestHandshakeAt,
      transferRx: client.transferRx,
      transferTx: client.transferTx,
    })),
  };
});
