import { RelayerReqestMoveSerialized, ImmutablesData, LimitOrderV4Struct, RelayerRequestEvm, isEvm } from "@1inch/cross-chain-sdk"
import express from "express"
import http from "http"
import { Server as WebSocketServer, WebSocket } from "ws"
import { Jsonify } from "type-fest"
const app = express()
const port = 20002
app.use(express.json())

export enum MessageType {
    NEW_ORDER = "NEW_ORDER",
    FILLED_ORDER = "FILLED_ORDER",
    DEPLOYED_DST_ESCROW = "DEPLOYED_DST_ESCROW",
    ORDER_SECRET_REVEALED = "ORDER_SECRET_REVEALED"
}

/// qouteId to boolean indicating if the order is ready for fill
const orderReadyForFill = new Map<string, boolean>()
const orderReadyForSecret = new Map<string, boolean>()
const orderType = new Map<string, "evm" | "movevm">()

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

const moveCrosschainOrderMap: {
    [qouteId: string]: MoveOrderstore
} = {}

const evmCrosschainOrderMap: {
    [qouteId: string]: EvmOrderStore
} = {}

// Create HTTP server and WebSocket server
const server = http.createServer(app)
const wss = new WebSocketServer({ server })

// Store connected clients
const clients = new Set<WebSocket>()

wss.on("connection", (ws: WebSocket) => {
    clients.add(ws)
    ws.on("close", () => {
        clients.delete(ws)
    })
    ws.on("open", () => {
        ws.send(JSON.stringify({}))
    })
    ws.on("message", (message) => {
        const parsedMessage = JSON.parse(message.toString())
        console.log("Received message:", parsedMessage)
        switch (parsedMessage.type) {
            case MessageType.FILLED_ORDER:
                if (orderType.get(parsedMessage.qouteId) === "evm") {
                    evmCrosschainOrderMap[parsedMessage.qouteId]!.srcImmutables = parsedMessage.srcImmutables
                    orderReadyForFill.set(parsedMessage.qouteId, true)
                    console.log("✅ Order filled and src escrow deployed successfully")
                } else {
                    moveCrosschainOrderMap[parsedMessage.qouteId]!.immutableId = parsedMessage.dstImmutables.immutables_id
                    moveCrosschainOrderMap[parsedMessage.qouteId]!.srcEscrowObjectId = parsedMessage.srcEscrowObjectId
                    console.log(moveCrosschainOrderMap[parsedMessage.qouteId])
                }
                break
            case MessageType.DEPLOYED_DST_ESCROW:
                console.log("🚀 Destination escrow deployed successfully!")
                if (orderType.get(parsedMessage.qouteId) === "evm") {
                    console.log("EVM order detected")
                    evmCrosschainOrderMap[parsedMessage.qouteId]!.dstImutablesId = parsedMessage.immutablesId
                    evmCrosschainOrderMap[parsedMessage.qouteId]!.dstEscrowObjectId = parsedMessage.dstEscrowObjectId
                    orderReadyForSecret.set(parsedMessage.qouteId, true)
                } else {
                    ///@ts-ignore
                    moveCrosschainOrderMap[parsedMessage.qouteId].dstImmutables = parsedMessage.dstImmutables
                    console.log(moveCrosschainOrderMap[parsedMessage.qouteId])
                    orderReadyForSecret.set(parsedMessage.qouteId, true)
                }
                break
            default:
                console.log("Received unknown message type:", parsedMessage)
        }

    })
})

app.post("/relayer/v1.1/submit", async (req, res) => {
    // Broadcast the order to all connected WebSocket clients
    const order = req.body
    console.log(order)
    orderReadyForFill.set(order.quoteId, true)
    orderReadyForSecret.set(order.quoteId, false)
    console.log("Broadcasting order:", order)
    for (const client of clients) {
        if (client.readyState === client.OPEN) {
            client.send(JSON.stringify({ type: MessageType.NEW_ORDER, order }))
        }
    }
    if (isEvm(order.srcChainId)) {
        evmCrosschainOrderMap[order.quoteId] = {
            innerOrder: order,
            srcImmutables: undefined,
            dstImutablesId: undefined,
            dstEscrowObjectId: undefined
        }
        orderType.set(order.quoteId, "evm")
    } else {
        moveCrosschainOrderMap[order.quoteId] = {
            innerOrder: order,
            dstImmutables: undefined,
            immutableId: undefined,
            srcEscrowObjectId: undefined
        }
        orderType.set(order.quoteId, "movevm")
    }
    res.status(200).json({ status: "Order broadcasted" })
})

app.get("/order/:qoute/ready-for-submit", (req, res) => {
    const qouteId = req.params.qoute;
    console.log("Checking order readiness for qouteId:", qouteId)
    const isReady = orderReadyForSecret.get(qouteId) ?? false;
    res.json({ readyForSubmit: isReady });
})

app.post("/relayer/v1.1/submit/secret", (req, res) => {
    const qouteId = req.body.orderHash
    const secret = req.body.secret

    if (orderReadyForSecret.get(qouteId)) {
        const order = orderType.get(qouteId) === "evm" ? evmCrosschainOrderMap[qouteId]! : moveCrosschainOrderMap[qouteId]!
        for (const client of clients) {
            if (client.readyState === client.OPEN) {
                client.send(JSON.stringify({ type: MessageType.ORDER_SECRET_REVEALED, qouteId, secret, order }))
            }
        }
        res.status(200).json({ status: "Secret submitted successfully" })
    } else {
        res.status(400).json({ error: "Order is not ready for secret submission" })
    }
})

app.get("/", (req, res) => {
    res.send("Hello World!")
})

server.listen(port, () => {
    console.log(`Server is running at http://localhost:${port}`)
    console.log(`WebSocket server is running at ws://localhost:${port}`)
})