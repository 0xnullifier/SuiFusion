import axios from "axios"
import { DstImmutablesComplement, isEvm, ESCROW_FACTORY, EvmAddress, EvmEscrowFactoryFacade, HashLock, Immutables, ImmutablesData, MoveVMFusionPackage, MoveVMSrcEscrowPackage, NetworkEnum, RelayerReqestMoveSerialized, SuiAddress, TimeLocks, EscrowExtension, Extension, LimitOrderV4Struct, EvmCrossChainOrder, TakerTraits, AmountMode, MoveVMDstEscrow, RelayerRequestEvm, } from "@1inch/cross-chain-sdk"
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { id, Interface, JsonRpcProvider, Signature, Wallet } from "ethers";
import WebSocket from "ws";
const ws = new WebSocket("ws://localhost:20002/ws");
import Resolver from "../Resolver.json"
import EscrowDst from "../EscrowDst.json"
import IEscrowFactory from "../EscrowFactory.json"
import EscrowSrc from "../EscrowSrc.json"
import { getFullnodeUrl, SuiClient } from "@mysten/sui/client";
import { fromHex, toHex } from "@mysten/sui/utils";
import { add0x } from "@1inch/byte-utils";
import { bcs } from "@mysten/sui/bcs";
import { Jsonify } from "type-fest"
const SUI_SCAN_TX = (tx: string) => "https://suiscan.xyz/testnet/tx/" + tx
const TENDER_TX = (tx: string) => "https://dashboard.tenderly.co/0xnullifier/project/testnet/87c016f5-3cb0-4a34-bf2f-6bfe8c1b02d7/tx" + tx


const keypair = Ed25519Keypair.fromSecretKey(process.env.SUI_PRIVATE_KEY!);
if (keypair.getPublicKey().toSuiAddress() !== "0x56a8c03c42263d494357a1ecdb97bc885b638b5896e334ed0caaf0335013578d") {
    throw new Error("Invalid SUI_PRIVATE_PHASE, please check the .env file");
}
const provider = new JsonRpcProvider("https://virtual.mainnet.eu.rpc.tenderly.co/702101b0-dd4e-4666-b035-a44ec54ea1e9");
const suiClient = new SuiClient({ url: getFullnodeUrl("testnet") })
const wallet = new Wallet(process.env.RESOLVER_PRIVATE_KEY!, provider);
const resolverContract = new Interface(Resolver.abi)
const resolverContractAddress = "0xb53249FEBB6562Abf19BD728d6775c09d2ae0438"
const escrowDstContract = new Interface(EscrowDst.abi)
const escrowSrcContract = new Interface(EscrowSrc.abi)
const escrowFactory = new Interface(IEscrowFactory.abi)
const SRC_ESCROW_TOPIC_HASH = escrowFactory.getEvent("SrcEscrowCreated")?.topicHash
if (!SRC_ESCROW_TOPIC_HASH) {
    throw new Error("SRC_ESCROW_TOPIC_HASH not found in EscrowFactory contract");
}

// const log = {
//     transactionHash: '0xe00519ac6888edb8928a9c69abd1dbbd5f71a0cf5d7594c81681638345d79c6f',
//     blockHash: '0x30cd25715580e3f50ab3067877d0073dee2142d1d2088e106e9a0e63c638d91c',
//     blockNumber: 23053304,
//     removed: undefined,
//     address: '0x31De30e2621D5AECd951F2661e2D03CDA27e2e83',
//     data: '0x477cd6bc5c33405f18447b5b9dca5e867797d62a0cbc9b32ee09f868108fad5830ef0471ae0949b0d1bfbb075f80f1edb03ba1c7ffb8955cedd137b5bda5428300000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c8000000000000000000000000e3e7a4b35574ce4b9bc661cd93e8804da548932a000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000002386f26fc1000000000000000000000000000000000000000000000000000000038d7ea4c68000688e1471000000b40000007800000000000000f0000000b400000078000000000000000000000000000000000d8e3f8b721a5f6355eee11e4b83645d7412cc0f000000000000000000000000000000000000000000000000000000026b1db12f587c29de216efd4219573e08a1f6964d4fa7cb714518c2c8a0f29abfa264327d00000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000000000000000259',
//     topics: [
//         '0x0e534c62f0afd2fa0f0fa71198e8aa2d549f24daf2bb47de0d5486c7ce9288ca'
//     ],
//     index: 1,
//     transactionIndex: 0
// }

// const decoded = escrowFactory.decodeEventLog(
//     "SrcEscrowCreated",
//     log.data,
//     log.topics
// );
// console.log("Decoded log:", decoded);
const moveVmFusionPackage = MoveVMFusionPackage.DEFAULT;

export enum MessageType {
    NEW_ORDER = "NEW_ORDER",
    FILLED_ORDER = "FILLED_ORDER",
    DEPLOYED_DST_ESCROW = "DEPLOYED_DST_ESCROW",
    ORDER_SECRET_REVEALED = "ORDER_SECRET_REVEALED",
    DST_ESCROW_WITHDRAWN = "DST_ESCROW_WITHDRAWN",
    SRC_ESCROW_WITHDRAWN = "SRC_ESCROW_WITHDRAWN"
}


interface MoveOrderstore {
    innerOrder: RelayerReqestMoveSerialized,
    dstImmutables?: ImmutablesData,
    immutableId?: string,
    srcEscrowObjectId?: string
}

type NonFunctionPropertyNames<T> = {
    [K in keyof T]: T[K] extends Function ? never : K;
}[keyof T];
type NonFunctionProperties<T> = Pick<T, NonFunctionPropertyNames<T>>;
export type DataFor<T> = NonFunctionProperties<T>;

interface EvmOrderStore {
    innerOrder: Jsonify<DataFor<RelayerRequestEvm>>,
    srcImmutables?: ImmutablesData,
    dstImutablesId?: string,
    dstEscrowObjectId?: string
}

const myOrders: string[] = [];

const metadataToCoinSymbolMap: {
    [address: string]: string
} = {
    "0x587c29de216efd4219573e08a1f6964d4fa7cb714518c2c8a0f29abfa264327d": "0x2::sui::SUI",
    "0x5a2d9b8a2cbea39a2ce6186a31031496dd02b3b3eef59b7962bd3e2f6ddd988f": "0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC",
}



ws.on("open", () => {
    console.log("WebSocket connection established");
});

ws.on("message", async (data) => {
    const message = JSON.parse(data.toString());
    switch (message.type) {
        case MessageType.NEW_ORDER:
            if (message.order) {
                const order = message.order;
                if (order.srcChainId === NetworkEnum.SUI) {
                    const orderId = order.orderId;
                    if (!orderId) {
                        console.error("no order id exiting")
                        return;
                    }
                    const tx = await moveVmFusionPackage.fillCrossChainOrder(orderId, BigInt(order.order.srcSafetyDeposit), BigInt(order.order.amount), order.order.srcToken, keypair)
                    if (!tx.objectChanges || !tx.events) {
                        console.error("No events in transaction:", tx);
                        return;
                    }
                    const createdObjects = tx.objectChanges.filter(changes => changes.type === "created")
                    const srcEscrowObjectId = createdObjects.find((object) => object.objectType.includes("FusionPlusSrcEscrow"))?.objectId

                    console.log(
                        `🚀 Src escrow  created on SUI!
                        🔑 Order Quote ID: ${order.quoteId}
                        Transation Digest: ${SUI_SCAN_TX(tx.digest)}
                        📦 Src Escrow Object ID: ${srcEscrowObjectId}
                        🌐 Src Chain ID: ${order.srcChainId}
                        `
                    )
                    if (!srcEscrowObjectId) {
                        console.error("no object id founds", tx)
                        return;
                    }
                    const dstImmutables = tx.events[0]?.parsedJson as {
                        dst_immutables: {
                            amount: string,
                            chainId: string,
                            maker: string,
                            safety_deposit: string,
                            token: string
                        },
                        immutables_id: string
                    };
                    ws.send(JSON.stringify({ type: MessageType.FILLED_ORDER, qouteId: order.quoteId, dstImmutables, srcEscrowObjectId, txHash: tx.digest }));

                    const immutablesId = dstImmutables.immutables_id;
                    const immutablesObject = await suiClient.getObject({
                        id: immutablesId,
                        options: {
                            showContent: true,
                        }
                    })
                    if (immutablesObject.data?.content?.dataType === "moveObject") {
                        ///@ts-ignore
                        const timelock = immutablesObject.data.content.fields.timelock.fields.inner;
                        ///@ts-ignore
                        const orderHash = Buffer.from(immutablesObject.data.content.fields.order_hash)
                        const srcImmutables = Immutables.new({
                            orderHash,
                            hashLock: HashLock.fromString(order.order.hashLock),
                            maker: SuiAddress.fromString(`0x${order.order.maker}`, false),
                            taker: SuiAddress.fromString(keypair.getPublicKey().toSuiAddress(), false),
                            token: SuiAddress.fromString(order.order.srcToken, true),
                            safetyDeposit: BigInt(order.order.srcSafetyDeposit),
                            amount: BigInt(order.order.amount),
                            timeLocks: TimeLocks.fromBigInt(BigInt(timelock))
                        })
                        // TODO: use all the things from sui event but for convience now
                        let dstImmutablesEvm = srcImmutables.withComplement(
                            DstImmutablesComplement.new({
                                maker: EvmAddress.fromString(order.order.receiver),
                                token: EvmAddress.fromString(order.order.dstToken),
                                amount: BigInt(dstImmutables.dst_immutables.amount),
                                safetyDeposit: BigInt(dstImmutables.dst_immutables.safety_deposit),
                                taker: EvmAddress.fromString(wallet.address)
                            })
                        )
                        console.log(dstImmutables)
                        console.log(dstImmutablesEvm.timeLocks.toDstTimeLocks().privateCancellation > srcImmutables.timeLocks.toSrcTimeLocks().privateCancellation)
                        console.log(resolverContract.encodeFunctionData('deployDst', [
                            dstImmutablesEvm.build(),
                            srcImmutables.timeLocks.toSrcTimeLocks().privateCancellation
                        ]))
                        const res = await wallet.sendTransaction({
                            to: resolverContractAddress,
                            data: resolverContract.encodeFunctionData('deployDst', [
                                dstImmutablesEvm.build(),
                                dstImmutablesEvm.timeLocks.toDstTimeLocks().privateCancellation * 2n,
                            ]),
                            value: dstImmutablesEvm.safetyDeposit,
                            gasLimit: 10000000
                        })

                        const receipt = await res.wait(1)
                        if (!receipt) {
                            console.error("No receipt found for transaction:", res);
                            return;
                        }
                        if (!receipt.status) {
                            console.error("Transaction failed:", res);
                            return;
                        }
                        const blockTimestamp = BigInt((await res.getBlock())!.timestamp)
                        dstImmutablesEvm = dstImmutablesEvm.withDeployedAt(blockTimestamp)
                        ws.send(JSON.stringify({
                            type: MessageType.DEPLOYED_DST_ESCROW,
                            qouteId: order.quoteId,
                            dstImmutables: dstImmutablesEvm.build(),
                            txHash: res.hash,
                        }));
                        myOrders.push(order.quoteId)
                        console.log(`🚀 Dst escrow deployed on EVM
                        Transaction Hash: ${TENDER_TX(res.hash)}
                        🔑 Order Quote ID: ${order.quoteId}
                        📦 Dst Immutables Object ID: ${immutablesId}
                        🌐 Src Chain ID: ${order.srcChainId}
                        🌐 Dst Chain ID: ${order.dstChainId}
                        👤 Maker: ${order.order.maker}
                        🎯 Receiver: ${order.order.receiver}
                        💰 Amount: ${order.order.amount.toString()}
                        ⏰ Timestamp: ${new Date().toISOString()}
                            !`);
                    } else { console.error("somethign went wrong"); return; }

                } else if (isEvm(order.srcChainId)) {
                    const escrowData = Extension.decode(order.extension);

                    const orderJson = order.order as LimitOrderV4Struct;
                    const orderEvm = EvmCrossChainOrder.fromDataAndExtension(orderJson, escrowData)
                    if (!(orderEvm.receiver instanceof SuiAddress)) {
                        console.error("Receiver is not a SuiAddress:", orderEvm.receiver);
                        return;
                    }

                    let srcImmutables = orderEvm.toSrcImmutables(
                        order.srcChainId,
                        EvmAddress.fromString(resolverContractAddress),
                        orderEvm.makingAmount
                    )
                    const takerTraits = TakerTraits.default()
                        .setAmountMode(AmountMode.maker)
                        .setExtension(orderEvm.extension)

                    const { r, yParityAndS: vs } = Signature.from(order.signature)
                    const { args, trait } = takerTraits.encode()

                    const data = resolverContract.encodeFunctionData('deploySrc', [
                        srcImmutables.build(),
                        orderEvm.build(),
                        r,
                        vs,
                        orderEvm.makingAmount,
                        trait,
                        args
                    ])
                    await new Promise(resolve => setTimeout(resolve, 14000));
                    let srcEscrow = await wallet.sendTransaction({
                        to: resolverContractAddress,
                        data,
                        value: orderEvm.srcSafetyDeposit,
                        gasLimit: 10000000,
                        from: wallet.getAddress()
                    })

                    const receipt = await srcEscrow.wait(1)
                    if (!receipt || !receipt.status) {
                        console.error("Transaction failed:", srcEscrow);
                        return;
                    }

                    const logs = receipt.logs.find(log => log.topics[0] === SRC_ESCROW_TOPIC_HASH)
                    if (!logs) {
                        console.error("No logs found for SRC_ESCROW_TOPIC_HASH in transaction:", receipt);
                        return;
                    }
                    const decoded = escrowFactory.decodeEventLog(
                        "SrcEscrowCreated",
                        logs.data,
                        logs.topics
                    );
                    /// the taking amount calculate from the extension
                    const takingAmount = decoded[1][1]

                    const blockTimestamp = BigInt((await srcEscrow.getBlock())!.timestamp)

                    srcImmutables = srcImmutables.withDeployedAt(blockTimestamp)
                    ws.send(JSON.stringify({
                        type: MessageType.FILLED_ORDER,
                        qouteId: order.quoteId,
                        srcImmutables: srcImmutables.build(),
                        srcChainId: order.srcChainId,
                        txHash: receipt.hash
                    }))

                    console.log(`🚀 Src escrow deployed on EVM! 
                    🔑 Order Quote ID: ${order.quoteId}
                    🧮 Taking Amount: ${takingAmount.toString()}
                    📦 Taker : ${srcImmutables.taker}
                    🌐 Src Chain ID: ${order.srcChainId}
                    👤 Maker: ${orderEvm.maker}
                    📝 Transaction Hash: ${TENDER_TX(srcEscrow.hash)}
                        `)
                    myOrders.push(order.quoteId)


                    let dstImmutables = srcImmutables.withComplement(
                        DstImmutablesComplement.new({
                            amount: takingAmount,
                            safetyDeposit: orderEvm.dstSafetyDeposit,
                            maker: orderEvm.receiver,
                            taker: SuiAddress.fromString(keypair.getPublicKey().toSuiAddress(), false),
                            token: SuiAddress.fromString(metadataToCoinSymbolMap[add0x(BigInt(orderEvm.takerAsset.toString()).toString(16))]!, true)
                        })
                    )
                    const result = await MoveVMDstEscrow.DEFAULT.createDstEscrow(dstImmutables, keypair)
                    if (!result.objectChanges || !result.events) {
                        console.error("No events in transaction:", result);
                        return;
                    }
                    const createdObjects = result.objectChanges.filter(changes => changes.type === "created")
                    const dstEscrowObjectId = createdObjects.find((object) => object.objectType.includes("FusionPlusDstEscrow"))?.objectId
                    const srcDstImmutables = createdObjects.find((object) => object.objectType.includes("SuiDstImmutables"))?.objectId

                    if (!dstEscrowObjectId || !srcDstImmutables) {
                        console.error("no object id founds", result)
                        return;
                    }
                    console.log(`🚀 Dst escrow deployed on Sui!
                    📝 Transaction Hash: ${SUI_SCAN_TX(result.digest)}
                    🔑 Order Quote ID: ${order.quoteId}
                    📦 Dst Escrow Object ID: ${dstEscrowObjectId}
                    🗂️ Immutables Object ID: ${srcDstImmutables}
                    🌐 Src Chain ID: ${order.srcChainId}
                    🌐 Dst Chain ID: ${order.dstChainId}
                    👤 Maker: ${orderEvm.maker}
                    🎯 Receiver: ${orderEvm.receiver}
                    💰 Amount: ${orderEvm.makingAmount.toString()}
                    🪙 Taker Asset: ${orderEvm.takerAsset.toString()}
                    ⏰ Timestamp: ${new Date().toISOString()}
                    `);


                    ws.send(JSON.stringify({
                        type: MessageType.DEPLOYED_DST_ESCROW,
                        qouteId: order.quoteId,
                        dstEscrowObjectId,
                        immutablesId: srcDstImmutables,
                        txHash: result.digest
                    }))
                } else {
                    console.log("Order is not implemented yet");
                    return;
                }
            } else {
                console.error("No order in message:", message);
            }
            break;
        case MessageType.ORDER_SECRET_REVEALED:
            console.log("Order secret revealed:", message);
            const { qouteId, secret, order } = message;
            if (!qouteId || !secret || !order) {
                console.error("Missing orderId, secret or order in message:", message);
                return;
            }
            if (myOrders.includes(qouteId)) {

                if (order.innerOrder.srcChainId === NetworkEnum.SUI && isEvm(order.innerOrder.dstChainId)) {

                    const typedOrder = order as MoveOrderstore;
                    if (!typedOrder.dstImmutables) {
                        console.error("No dstImmutables in order:", typedOrder);
                        return;
                    }
                    const srcEscrowObjectId = typedOrder.srcEscrowObjectId;
                    if (!srcEscrowObjectId) {
                        console.error("No srcEscrowObjectId in order:", typedOrder);
                        return;
                    }
                    const immutablesId = typedOrder.immutableId;
                    if (!immutablesId) {
                        console.error("No immutablesId in order:", typedOrder);
                        return;
                    }
                    const dstImplAddress = await provider.call({
                        ///@ts-ignore
                        to: ESCROW_FACTORY[typedOrder.innerOrder.dstChainId].toString(),
                        data: id('ESCROW_DST_IMPLEMENTATION()').slice(0, 10)
                    })

                    const dstEscrowAddress = EvmEscrowFactoryFacade.getFactory(
                        typedOrder.innerOrder.dstChainId,
                        ///@ts-ignore
                        ESCROW_FACTORY[typedOrder.innerOrder.dstChainId]
                    ).getSrcEscrowAddress(Immutables.fromJSON(typedOrder.dstImmutables), EvmAddress.fromString(add0x(dstImplAddress.slice(-40))))

                    const dstImmutables = Immutables.fromJSON(typedOrder.dstImmutables);
                    console.log("dstEscrowAddress", dstEscrowAddress)
                    const dstWithdraw = await wallet.sendTransaction({
                        to: dstEscrowAddress.toString(),
                        data: escrowDstContract.encodeFunctionData('withdraw', [
                            add0x(secret),
                            dstImmutables.build(),
                        ]),
                        from: wallet.getAddress(),
                        gasLimit: 10000000
                    })
                    const receipt = await dstWithdraw.wait(1)
                    if (!receipt || !receipt.status) {
                        console.error("Transaction failed:", dstWithdraw);
                        return;
                    }
                    ws.send(JSON.stringify({
                        type: MessageType.DST_ESCROW_WITHDRAWN,
                        qouteId: typedOrder.innerOrder.quoteId,
                        txhash: receipt.hash,
                    }))

                    const srcWithdraw = await MoveVMSrcEscrowPackage.DEFAULT.withdrawTo(
                        srcEscrowObjectId,
                        immutablesId,
                        typedOrder.innerOrder.order.srcToken,
                        keypair,
                        fromHex(add0x(secret))
                    )
                    ws.send(JSON.stringify({
                        type: MessageType.SRC_ESCROW_WITHDRAWN,
                        qouteId: typedOrder.innerOrder.quoteId,
                        txhash: srcWithdraw.digest,
                    }))
                    console.log('src escrow withdrawn', SUI_SCAN_TX(srcWithdraw.digest));

                } else if (isEvm(order.innerOrder.srcChainId)) {
                    const evmCrosschainOrderMap = order as EvmOrderStore;
                    if (!evmCrosschainOrderMap.srcImmutables) {
                        console.error("No srcImmutables in order:", evmCrosschainOrderMap);
                        return;
                    }
                    if (!evmCrosschainOrderMap.dstImutablesId || !evmCrosschainOrderMap.dstEscrowObjectId) {
                        console.error("No dstImmutablesId or dstEscrowObjectId in order:", evmCrosschainOrderMap);
                        return;
                    }
                    const orderEvm = EvmCrossChainOrder.fromDataAndExtension(evmCrosschainOrderMap.innerOrder.order, Extension.decode(evmCrosschainOrderMap.innerOrder.extension));
                    const srcImmutables = Immutables.fromJSON(evmCrosschainOrderMap.srcImmutables);
                    const dstImmutablesId = evmCrosschainOrderMap.dstImutablesId;
                    const dstEscrowObjectId = evmCrosschainOrderMap.dstEscrowObjectId;
                    if (!metadataToCoinSymbolMap[add0x(BigInt(orderEvm.takerAsset.toString()).toString(16))]) {
                        console.error("No metadata for coin symbol:", orderEvm.takerAsset.toString());
                        return;
                    }
                    const res = await MoveVMDstEscrow.DEFAULT.resolverWithdraw(
                        fromHex(add0x(secret)),
                        dstImmutablesId,
                        dstEscrowObjectId,
                        keypair,
                        metadataToCoinSymbolMap[add0x(BigInt(orderEvm.takerAsset.toString()).toString(16))]!
                    )
                    ws.send(JSON.stringify({
                        type: MessageType.DST_ESCROW_WITHDRAWN,
                        qouteId: evmCrosschainOrderMap.innerOrder.quoteId,
                        txhash: res.digest,
                    }))
                    console.log('dst escrow withdrawn', SUI_SCAN_TX(res.digest));

                    const srcImplAddress = await provider.call({
                        ///@ts-ignore
                        to: ESCROW_FACTORY[evmCrosschainOrderMap.innerOrder.srcChainId].toString(),
                        data: id('ESCROW_SRC_IMPLEMENTATION()').slice(0, 10)
                    })

                    const srcEscrowAddress = EvmEscrowFactoryFacade.getFactory(
                        order.srcChain,
                        ///@ts-ignore
                        ESCROW_FACTORY[evmCrosschainOrderMap.innerOrder.srcChainId]
                    ).getSrcEscrowAddress(
                        srcImmutables as Immutables<EvmAddress>,
                        EvmAddress.fromString(add0x(srcImplAddress.slice(-40))) // decode from bytes32
                    )

                    const srcWithdraw = await wallet.sendTransaction({
                        to: srcEscrowAddress.toString(),
                        data: escrowSrcContract.encodeFunctionData('withdraw', [
                            add0x(secret),
                            srcImmutables.build(),
                        ]),
                        from: wallet.getAddress(),
                        gasLimit: 10000000
                    })
                    const receipt = await srcWithdraw.wait(1)
                    if (!receipt || !receipt.status) {
                        console.error("Transaction failed:", srcWithdraw);
                        return;
                    }
                    console.log('src escrow withdrawn', TENDER_TX(receipt.hash));

                    ws.send(JSON.stringify({
                        type: MessageType.SRC_ESCROW_WITHDRAWN,
                        qouteId: evmCrosschainOrderMap.innerOrder.quoteId,
                        txhash: receipt.hash,
                    }))
                }
            }
            break;

        default:
            console.log("Unknown message", message);
            break;
    }
});

ws.on("close", () => {
    console.log("WebSocket connection closed");
});

ws.on("error", (err) => {
    console.error("WebSocket error:", err);
});