import { QuoterApi, HttpProviderConnector, QuoterRequest, NetworkEnum, MoveVmCrossChainOrderParamsData, HashLock, EvmAddress, OrdersApi, RelayerApi, RelayerRequestMoveVM, MoveVMFusionPackage, RelayerRequestEvm, SuiAddress } from '@1inch/cross-chain-sdk';
import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import axios from 'axios';
import { JsonRpcApiProvider, JsonRpcProvider, keccak256, Wallet } from 'ethers';

const httpClient: HttpProviderConnector = {
    async get(url) {
        const data = await axios.get(url);
        return data.data;
    },
    async post(url, data) {
        const res = await axios.post(url, data);
        return res.data
    }
}

async function main() {
    console.log("🚀 Starting EVM ➡️ SUI cross-chain order script...");
    const qouter = new QuoterApi(
        {
            url: 'http://localhost:20001/quoter'
        },
        httpClient
    )
    const provider = new JsonRpcProvider("https://virtual.mainnet.eu.rpc.tenderly.co/702101b0-dd4e-4666-b035-a44ec54ea1e9");
    const wallet = new Wallet(process.env.MAKER_PRIVATE_KEY_ETH!, provider)
    const srcChain = NetworkEnum.ETHEREUM;
    const suiClient = new SuiClient({ url: getFullnodeUrl("testnet") })

    console.log("🔍 Fetching SUI coin metadata...");
    const coinMetaData = await suiClient.getCoinMetadata({
        coinType: '0x2::sui::SUI',
    })
    if (!coinMetaData?.id) {
        console.log("❌ Failed to fetch SUI coin metadata!");
        return;
    }
    console.log("✅ SUI Coin Metadata ID:", coinMetaData.id)

    console.log("📝 Building quote request for EVM ➡️ SUI...");
    const params = QuoterRequest.forEvmToMoveVm({
        srcChain: NetworkEnum.ETHEREUM,
        dstChain: NetworkEnum.SUI,
        srcTokenAddress: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2', // weth
        dstTokenAddress: coinMetaData.id, //
        amount: 1e14.toString(), // 0.0001 ETH 
        walletAddress: wallet.address
    })

    console.log("🔗 Requesting quote from Quoter API...");
    const res = await qouter.getQuote(params)
    console.log("📦 Quote response:", res)
    if (!res.quoteId) {
        console.log("❌ No quoteId received, aborting!");
        throw new Error("did not work")
    }
    const quoteId = res.quoteId
    console.log("🆔 Received quoteId:", quoteId);

    const secret = Buffer.from(Array.from({ length: 32 }, () => Math.floor(Math.random() * 256))).toString('hex');
    console.log("🔒 Generated secret for hashlock:", secret);

    const order = res.createEvmOrder({
        hashLock: HashLock.forSingleFill(`0x${secret}`),
        receiver: SuiAddress.fromString("0x1ea0a252dfc725efaa13ce9c0d8e3f8b721a5f6355eee11e4b83645d7412cc0f", false),
    })
    console.log("📝 Created EVM order:", order)
    console.log("👤 Order receiver:", order.receiver.toString())
    console.log("💰 Order takerAsset:", order.takerAsset.toString())

    const typedData = order.getTypedData(srcChain)
    console.log("✍️ Signing order...");
    const signature = await wallet.signTypedData(
        typedData.domain,
        { Order: typedData.types[typedData.primaryType]! },
        typedData.message
    )
    console.log("🖋️ Signature:", signature);

    const relayerRequest = new RelayerRequestEvm({
        order: order.toJSON(),
        quoteId: res.quoteId,
        secretHashes: [HashLock.forSingleFill(`0x${secret}`).toString()],
        signature,
        extension: order.escrowExtension.build().encode(),
        srcChainId: srcChain,
    })

    const relayerApi = new RelayerApi(
        {
            url: 'http://localhost:20002/relayer'
        },
        httpClient
    )

    console.log("📤 Submitting order to relayer...");
    await relayerApi.submit(relayerRequest)
    console.log('✅ Order submitted to relayer:', relayerRequest)

    let isReady = false
    console.log("⏳ Waiting for order to be ready for secret submission...");
    const interval = setInterval(async () => {
        try {
            const apiRes = await axios.get(`http://localhost:20002/order/${quoteId}/ready-for-submit`);
            isReady = apiRes.data.readyForSubmit;
            console.log(`🔄 Order with quoteId ${quoteId} ready for submission:`, isReady ? "✅ Yes" : "❌ No");
            if (isReady) {
                console.log("🚦 Order is ready! Submitting secret...");
                await relayerApi.submitSecret(quoteId, secret);
                console.log("🎉 Secret submitted! Process complete.");
                clearInterval(interval as NodeJS.Timeout);
                process.exit(0);
            }
        } catch (error) {
            console.error('⚠️ Error checking order status:', error);
        }
    }, 10000);

}

export { main as evmToSuiMain };
