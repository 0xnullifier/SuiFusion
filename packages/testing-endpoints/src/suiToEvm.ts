import { QuoterApi, HttpProviderConnector, QuoterRequest, NetworkEnum, MoveVmCrossChainOrderParamsData, HashLock, EvmAddress, OrdersApi, RelayerApi, RelayerRequestMoveVM, MoveVMFusionPackage, RelayerRequestEvm, SuiAddress } from '@1inch/cross-chain-sdk';
import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import axios from 'axios';
import { JsonRpcApiProvider, JsonRpcProvider, keccak256, Wallet } from 'ethers';

const httpClient: HttpProviderConnector = {
    async get(url) {
        // Mock implementation of the GET request
        const data = await axios.get(url);
        return data.data;
    },
    async post(url, data) {
        const res = await axios.post(url, data);
        return res.data
    }
}

async function main() {
    console.log('🚀 Starting SUI to EVM cross-chain order process...');

    const qouter = new QuoterApi(
        {
            url: 'http://localhost:20001/quoter'
        },
        httpClient
    )

    console.log('📝 Building quote request for MoveVM to EVM...');
    const params2 = QuoterRequest.forMoveVmToEvm({
        srcChain: NetworkEnum.SUI,
        dstChain: NetworkEnum.ETHEREUM,
        srcTokenAddress: '0x2::sui::SUI', //
        dstTokenAddress: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2', // weth
        amount: '10000000', // 0.01 SUI
        walletAddress: '0x1ea0a252dfc725efaa13ce9c0d8e3f8b721a5f6355eee11e4b83645d7412cc0f'
    })

    console.log('💬 Requesting quote from Quoter API...');

    const res2 = await qouter.getQuote(params2)
    if (!res2.quoteId) {
        console.log('❌ Quote request failed! Exiting...');
        throw new Error("did not work")
    }
    const quoteId = res2.quoteId
    console.log(`✅ Received quoteId: ${quoteId}`);

    const secret = Buffer.from(Array.from({ length: 32 }, () => Math.floor(Math.random() * 256))).toString('hex');
    console.log('🔑 Generated secret for hashlock:', secret);

    const params: MoveVmCrossChainOrderParamsData = {
        hashlock: HashLock.forSingleFill(`0x${secret}`),
        reciever: EvmAddress.fromString('0x809AEE083aC34B53F302986A38549c7A186a712F')
    }
    const keypair = Ed25519Keypair.fromSecretKey(process.env.MAKER_PRIVATE_KEY!)
    console.log('🔐 SUI Public Key:', keypair.getPublicKey().toSuiAddress())

    console.log('🛠️ Creating MoveVM order...');
    const order = res2.createMoveVmOrder(params)
    console.log('📦 Submitting cross-chain order to SUI...');
    const txResult = await MoveVMFusionPackage.DEFAULT.createCrossChainOrder(order, keypair)
    console.log('📝 Transaction Result:', txResult)
    const objectId = txResult.objectChanges?.find(change => change.type === 'created')?.objectId;
    if (!objectId) {
        console.log('❌ Object Id not found in transaction result! Exiting...');
        throw new Error("Object Id not found")
    }
    console.log('🆔 Created order objectId:', objectId);

    const relayerRequest = new RelayerRequestMoveVM({
        orderId: objectId,
        order: order.toJSON(),
        quoteId: res2.quoteId,
        secretHashes: [params.hashlock.toString()]
    })

    const relayerApi = new RelayerApi(
        {
            url: 'http://localhost:20002/relayer'
        },
        httpClient
    )

    console.log('📡 Submitting order to relayer...');
    await relayerApi.submit(relayerRequest)
    console.log('✅ Order submitted to relayer:', relayerRequest)
    let isReady = false
    console.log('⏳ Waiting for order to be ready for secret submission...');
    const interval = setInterval(async () => {
        try {
            const apiRes = await axios.get(`http://localhost:20002/order/${quoteId}/ready-for-submit`);
            isReady = apiRes.data.readyForSubmit;
            console.log(`🔄 Order with quoteId ${quoteId} is ready for submission:`, isReady ? '✅ Yes' : '❌ No');
            if (isReady) {
                console.log('🚦 Order is ready! Submitting secret to relayer...');
                await relayerApi.submitSecret(quoteId, secret);
                console.log('🎉 Secret submitted! Process complete.');
                clearInterval(interval as NodeJS.Timeout);
                process.exit(0);
            }
        } catch (error) {
            console.error('⚠️ Error checking order status:', error);
        }
    }, 10000);

}

export { main as suiToEvmMain };