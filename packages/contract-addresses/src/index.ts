import addresses from '../addresses.json';

export interface ContractAddresses {
    erc20Proxy: string;
    erc721Proxy: string;
    zrxToken: string;
    etherToken: string;
    exchangeV2: string;
    exchange: string;
    assetProxyOwner: string;
    zeroExGovernor: string;
    forwarder: string;
    coordinatorRegistry: string;
    coordinator: string;
    multiAssetProxy: string;
    staticCallProxy: string;
    erc1155Proxy: string;
    devUtils: string;
    zrxVault: string;
    staking: string;
    stakingProxy: string;
    erc20BridgeProxy: string;
    erc20BridgeSampler: string;
    chaiBridge: string;
    dydxBridge: string;
    godsUnchainedValidator: string;
    broker: string;
    chainlinkStopLimit: string;
    maximumGasPrice: string;
    dexForwarderBridge: string;
    exchangeProxyGovernor: string;
    exchangeProxy: string;
    exchangeProxyTransformerDeployer: string;
    exchangeProxyFlashWallet: string;
    exchangeProxyLiquidityProviderSandbox: string;
    zrxTreasury: string;
    transformers: {
        wethTransformer: string;
        payTakerTransformer: string;
        fillQuoteTransformer: string;
        affiliateFeeTransformer: string;
        positiveSlippageFeeTransformer: string;
    };
}

export enum ChainId {
    Mainnet = 1,
    Ropsten = 3,
    Rinkeby = 4,
    Kovan = 42,
    Ganache = 1337,
    BSC = 56,
    Polygon = 137,
    PolygonMumbai = 80001,
    Avalanche = 43114,
}

/**
 * Used to get addresses of contracts that have been deployed to either the
 * Ethereum mainnet or a supported testnet. Throws if there are no known
 * contracts deployed on the corresponding chain.
 * @param chainId The desired chainId.
 * @returns The set of addresses for contracts which have been deployed on the
 * given chainId.
 */
export function getContractAddressesForChainOrThrow(chainId: ChainId): ContractAddresses {
    const chainToAddresses: { [chainId: number]: ContractAddresses } = addresses;

    if (chainToAddresses[chainId] === undefined) {
        throw new Error(`Unknown chain id (${chainId}). No known 0x contracts have been deployed on this chain.`);
    }
    return chainToAddresses[chainId];
}
