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
    const qouter = new QuoterApi(
        {
            url: 'http://localhost:20001/quoter'
        },
        httpClient
    )
    const provider = new JsonRpcProvider("https://virtual.mainnet.eu.rpc.tenderly.co/5a73a2c7-48c3-458f-8f85-63456e9791bf");
    const wallet = new Wallet(process.env.MAKER_PRIVATE_KEY_ETH!, provider)
    const srcChain = NetworkEnum.ETHEREUM;
    const suiClient = new SuiClient({ url: getFullnodeUrl("testnet") })
    const coinMetaData = await suiClient.getCoinMetadata({
        coinType: '0x2::sui::SUI',
    })
    if (!coinMetaData?.id) return;
    console.log("Coin Metadata:", coinMetaData.id)

    const params = QuoterRequest.forEvmToMoveVm({
        srcChain: NetworkEnum.ETHEREUM,
        dstChain: NetworkEnum.SUI,
        srcTokenAddress: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2', // weth
        dstTokenAddress: coinMetaData.id, //
        amount: 1e14.toString(), // 0.0001 ETH 
        walletAddress: wallet.address
    })

    const res = await qouter.getQuote(params)
    console.log(res)
    if (!res.quoteId) {
        throw new Error("did not work")
    }
    const quoteId = res.quoteId
    const secret = Buffer.from(Array.from({ length: 32 }, () => Math.floor(Math.random() * 256))).toString('hex');
    const order = res.createEvmOrder({
        hashLock: HashLock.forSingleFill(`0x${secret}`),
        receiver: SuiAddress.fromString("0x1ea0a252dfc725efaa13ce9c0d8e3f8b721a5f6355eee11e4b83645d7412cc0f", false),
    })
    console.log("Order:", order)
    console.log(order.receiver.toString())
    console.log(order.takerAsset.toString())
    const typedData = order.getTypedData(srcChain)
    const signature = await wallet.signTypedData(
        typedData.domain,
        { Order: typedData.types[typedData.primaryType]! },
        typedData.message
    )
    const relayerRequest = new RelayerRequestEvm({
        order: order.toJSON(),
        quoteId: res.quoteId,
        secretHashes: [HashLock.forSingleFill(`0x${secret}`).toString()],
        signature,
        extension: order.escrowExtension.build().encode(),
        srcChainId: srcChain,
    })

    // const params2 = QuoterRequest.forMoveVmToEvm({
    //     srcChain: NetworkEnum.SUI,
    //     dstChain: NetworkEnum.ETHEREUM,
    //     srcTokenAddress: '0x2::sui::SUI', //
    //     dstTokenAddress: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2', // weth
    //     amount: '10000000', // 0.01 SUI
    //     walletAddress: '0x1ea0a252dfc725efaa13ce9c0d8e3f8b721a5f6355eee11e4b83645d7412cc0f'
    // })
    // const res2 = await qouter.getQuote(params2)
    // if (!res2.quoteId) {
    //     throw new Error("did not work")
    // }
    // const quoteId = res2.quoteId
    // const secret = Buffer.from(Array.from({ length: 32 }, () => Math.floor(Math.random() * 256))).toString('hex');
    // const params: MoveVmCrossChainOrderParamsData = {
    //     hashlock: HashLock.forSingleFill(`0x${secret}`),
    //     reciever: EvmAddress.fromString('0x809AEE083aC34B53F302986A38549c7A186a712F')
    // }
    // const keypair = Ed25519Keypair.fromSecretKey(process.env.MAKER_PRIVATE_KEY!)
    // console.log(keypair.getPublicKey().toSuiAddress())

    // const order = res2.createMoveVmOrder(params)
    // const txResult = await MoveVMFusionPackage.DEFAULT.createCrossChainOrder(order, keypair)
    // console.log(txResult)
    // const objectId = txResult.objectChanges?.find(change => change.type === 'created')?.objectId;
    // if (!objectId) {
    //     throw new Error("Object Id not found")
    // }

    // const relayerRequest = new RelayerRequestMoveVM({
    //     orderId: objectId,
    //     order: order.toJSON(),
    //     quoteId: res2.quoteId,
    //     secretHashes: [params.hashlock.toString()]
    // })


    const relayerApi = new RelayerApi(
        {
            url: 'http://localhost:20002/relayer'
        },
        httpClient
    )

    await relayerApi.submit(relayerRequest)
    console.log('Order submitted to relayer:', relayerRequest)
    let isReady = false
    const interval = setInterval(async () => {
        try {
            const apiRes = await axios.get(`http://localhost:20002/order/${quoteId}/ready-for-submit`);
            isReady = apiRes.data.readyForSubmit;
            console.log(`Order with quoteId ${quoteId} is ready for submission:`, isReady);
            if (isReady) {
                await relayerApi.submitSecret(quoteId, secret);
                clearInterval(interval as NodeJS.Timeout);
                process.exit(0);
            }
        } catch (error) {
            console.error('Error checking order status:', error);
        }
    }, 10000);

}

main()