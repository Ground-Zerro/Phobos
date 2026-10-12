import { defineStore } from 'pinia';
import { sha256 } from 'js-sha256';
import type { TypedInternalResponse } from 'nitropack/types';

type WGClientReturn = TypedInternalResponse<
  '/api/client',
  unknown,
  'get'
>[number];

type TransferSeries = { name: string; data: number[] }[];

type ClientRuntime = {
  transferRxHistory: number[];
  transferRxPrevious: number;
  transferRxCurrent: number;
  transferRxSeries: TransferSeries;
  transferTxHistory: number[];
  transferTxPrevious: number;
  transferTxCurrent: number;
  transferTxSeries: TransferSeries;
};

export type LocalClient = WGClientReturn & {
  avatar?: string;
} & Pick<
    ClientRuntime,
    | 'transferRxCurrent'
    | 'transferRxSeries'
    | 'transferTxCurrent'
    | 'transferTxSeries'
  >;

const HISTORY_LENGTH = 50;

function gravatarUrl(name: string): string | undefined {
  if (!name.includes('@') || !name.includes('.')) {
    return undefined;
  }
  return `https://gravatar.com/avatar/${sha256(name.toLowerCase().trim())}.jpg`;
}

function createRuntime(client: WGClientReturn): ClientRuntime {
  return {
    transferRxHistory: Array(HISTORY_LENGTH).fill(0),
    transferRxPrevious: client.transferRx ?? 0,
    transferRxCurrent: 0,
    transferRxSeries: [],
    transferTxHistory: Array(HISTORY_LENGTH).fill(0),
    transferTxPrevious: client.transferTx ?? 0,
    transferTxCurrent: 0,
    transferTxSeries: [],
  };
}

function advance(
  runtime: ClientRuntime,
  client: WGClientReturn,
  updateCharts: boolean
) {
  const rx = client.transferRx ?? 0;
  const tx = client.transferTx ?? 0;
  runtime.transferRxCurrent = rx - runtime.transferRxPrevious;
  runtime.transferRxPrevious = rx;
  runtime.transferTxCurrent = tx - runtime.transferTxPrevious;
  runtime.transferTxPrevious = tx;

  if (!updateCharts) {
    return;
  }

  runtime.transferRxHistory.push(runtime.transferRxCurrent);
  runtime.transferRxHistory.shift();
  runtime.transferTxHistory.push(runtime.transferTxCurrent);
  runtime.transferTxHistory.shift();
  runtime.transferRxSeries = [{ name: 'Rx', data: runtime.transferRxHistory }];
  runtime.transferTxSeries = [{ name: 'Tx', data: runtime.transferTxHistory }];
}

export const useClientsStore = defineStore('Clients', () => {
  const globalStore = useGlobalStore();
  const clients = ref<null | LocalClient[]>(null);
  const runtimes = new Map<number, ClientRuntime>();
  const avatars = new Map<string, string | undefined>();

  const searchParams = ref({
    filter: undefined as string | undefined,
  });

  const { data: fetchedClients, refresh: refetch } = useFetch('/api/client', {
    method: 'get',
    params: searchParams,
  });

  function avatarFor(name: string) {
    if (!avatars.has(name)) {
      avatars.set(name, gravatarUrl(name));
    }
    return avatars.get(name);
  }

  function prune(present: ReadonlySet<number>) {
    for (const id of runtimes.keys()) {
      if (!present.has(id)) {
        runtimes.delete(id);
      }
    }
  }

  function sorted(list: LocalClient[]) {
    return sortByProperty(list, 'name', globalStore.sortClient);
  }

  async function refresh({ updateCharts = false } = {}) {
    await refetch();
    const fetched = fetchedClients.value;
    if (!fetched) {
      clients.value = null;
      return;
    }

    const present = new Set<number>();
    const transformed = fetched.map((client): LocalClient => {
      present.add(client.id);
      let runtime = runtimes.get(client.id);
      if (!runtime) {
        runtime = createRuntime(client);
        runtimes.set(client.id, runtime);
      }
      advance(runtime, client, updateCharts);

      return {
        ...client,
        avatar: avatarFor(client.name),
        transferRxCurrent: runtime.transferRxCurrent,
        transferRxSeries: runtime.transferRxSeries,
        transferTxCurrent: runtime.transferTxCurrent,
        transferTxSeries: runtime.transferTxSeries,
      };
    });

    if (!searchParams.value.filter) {
      prune(present);
    }

    clients.value = sorted(transformed);
  }

  function resort() {
    if (clients.value) {
      clients.value = sorted([...clients.value]);
    }
  }

  function setSearchQuery(filter: string) {
    clients.value = null;
    searchParams.value.filter = filter || undefined;
  }

  return { clients, refresh, resort, setSearchQuery };
});
