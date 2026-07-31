import type { WarpRegistrationType } from '#db/repositories/warp/types';

const WARP_API_BASE = 'https://api.cloudflareclient.com/v0a4005';
const WARP_CLIENT_VERSION = 'a-6.30-3596';

type WarpAddresses = { v4?: string; v6?: string };

type WarpPeer = {
  public_key?: string;
  endpoint?: { host?: string };
};

type WarpRegConfig = {
  client_id?: string;
  interface?: { addresses?: WarpAddresses };
  peers?: WarpPeer[];
};

type WarpRegResponse = {
  id?: string;
  token?: string;
  account?: { license?: string };
  config?: WarpRegConfig;
};

function parseWarpError(body: string): string {
  try {
    const env = JSON.parse(body) as {
      errors?: { message?: string }[];
    };
    const message = env.errors?.[0]?.message;
    return message ?? '';
  } catch {
    return '';
  }
}

function parseRegistration(
  rsp: WarpRegResponse,
  privateKey: string
): WarpRegistrationType {
  const deviceId = rsp.id;
  const accessToken = rsp.token;
  const license = rsp.account?.license;

  if (!deviceId || !accessToken || !license) {
    throw new Error(
      'WARP registration: missing id, token or license in response'
    );
  }

  const config = rsp.config ?? {};
  const peer = config.peers?.[0];
  const peerPublicKey = peer?.public_key;
  const endpointHost = peer?.endpoint?.host;
  const addresses = config.interface?.addresses ?? {};

  if (!peerPublicKey || !endpointHost) {
    throw new Error(
      'WARP registration: missing peer public key or endpoint in response'
    );
  }

  return {
    accessToken,
    deviceId,
    licenseKey: license,
    privateKey,
    clientId: config.client_id ?? '',
    peerPublicKey,
    endpoint: endpointHost,
    addressV4: addresses.v4 ?? '',
    addressV6: addresses.v6 ?? '',
  };
}

type RequestOptions = {
  token?: string;
  clientVersion?: boolean;
  body?: unknown;
};

async function request(
  method: string,
  path: string,
  options: RequestOptions = {}
): Promise<string> {
  const headers: Record<string, string> = {};
  if (options.token) {
    headers.Authorization = `Bearer ${options.token}`;
  }
  if (options.clientVersion) {
    headers['CF-Client-Version'] = WARP_CLIENT_VERSION;
  }
  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);

  try {
    const response = await fetch(`${WARP_API_BASE}${path}`, {
      method,
      headers,
      body:
        options.body !== undefined ? JSON.stringify(options.body) : undefined,
      signal: controller.signal,
    });

    const text = await response.text();

    if (!response.ok) {
      const message = parseWarpError(text);
      throw new Error(
        message ||
          `WARP API ${method} ${path} returned status ${response.status}`
      );
    }

    return text;
  } finally {
    clearTimeout(timeout);
  }
}

export const warpApi = {
  async register(
    privateKey: string,
    publicKey: string
  ): Promise<WarpRegistrationType> {
    const body = {
      key: publicKey,
      tos: new Date().toISOString(),
      type: 'PC',
      model: 'PhobosWG',
      name: 'PhobosWG',
    };

    const text = await request('POST', '/reg', {
      clientVersion: true,
      body,
    });

    return parseRegistration(JSON.parse(text) as WarpRegResponse, privateKey);
  },

  async getConfig(deviceId: string, token: string): Promise<unknown> {
    const text = await request('GET', `/reg/${deviceId}`, { token });
    return JSON.parse(text);
  },

  async setLicense(
    deviceId: string,
    token: string,
    license: string
  ): Promise<void> {
    const text = await request('PUT', `/reg/${deviceId}/account`, {
      token,
      body: { license },
    });

    const response = JSON.parse(text) as { id?: string };
    if (!response.id) {
      throw new Error(`WARP set license failed: unexpected response: ${text}`);
    }
  },
};

export const warpClientTestExports = { parseWarpError, parseRegistration };
