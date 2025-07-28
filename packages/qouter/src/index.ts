import { QuoterResponse, QuoterRequestParams, NetworkEnum, SupportedChain, PresetEnum, ESCROW_FACTORY } from "@1inch/cross-chain-sdk"
import express from "express"
import { v4 as uuidv4 } from 'uuid';

const app = express()
const port = 20001

const metadataToCoinSymbolMap: {
    [address: string]: string
} = {
    "0x587c29de216efd4219573e08a1f6964d4fa7cb714518c2c8a0f29abfa264327d": "SUI"
}

export const MOBULA_API_BATCH_DATA = async (chain: string, address?: string, symbol?: string,) => {
    if (!symbol && !address) throw new Error("Either symbol or address must be provided")
    if (symbol) {
        console.log("calling mobula api for ", symbol, chain);
        const data = await fetch("https://api.mobula.io/api/1/market/data?symbol=" + symbol + "&blockchain=" + chain)
        const json = await data.json()
        return json.data
    }
    if (address) {
        console.log("calling mobula api for", address, chain)
        const data = await fetch("https://api.mobula.io/api/1/market/data?asset=" + address + "&blockchain=" + chain)
        const json = await data.json()
        return json.data
    }
}
const supportedChainToString = (chain: SupportedChain) => {
    switch (chain) {
        case NetworkEnum.SUI:
            return "SUI"
        default:
            return NetworkEnum[chain]
    }
}

const tokenData = async (request: QuoterRequestParams) => {
    const { srcChain, srcTokenAddress, dstChain, dstTokenAddress } = request
    let srcTokenData: any = null;
    let dstTokenData: any = null;
    if (srcChain == NetworkEnum.SUI) {
        if (!srcTokenAddress.includes('0x')) {
            throw new Error("Invalid token address")
        }
        const srcTokenSymbol = srcTokenAddress.split("::")[2]
        if (!srcTokenSymbol) {
            throw new Error("Invalid sui token address")
        }
        srcTokenData = await MOBULA_API_BATCH_DATA(supportedChainToString(srcChain), undefined, srcTokenSymbol)
    }
    if (dstChain == NetworkEnum.SUI) {
        // we are given coin metadata
        if (!dstTokenAddress.includes('0x')) {
            throw new Error("Invalid token address")
        }
        const dstTokenSymbol = metadataToCoinSymbolMap[dstTokenAddress]
        if (!dstTokenSymbol) {
            throw new Error("No metadata found for the given address")
        }
        dstTokenData = await MOBULA_API_BATCH_DATA(supportedChainToString(dstChain), undefined, dstTokenSymbol)
        console.log(dstTokenData)
    }
    if (!srcTokenData) {
        srcTokenData = await MOBULA_API_BATCH_DATA(supportedChainToString(srcChain), srcTokenAddress)
    }
    if (!dstTokenData) {
        dstTokenData = await MOBULA_API_BATCH_DATA(supportedChainToString(dstChain), dstTokenAddress)
    }
    return {
        srcTokenData,
        dstTokenData
    }
}
app.get("/quoter/v1.1/quote/receive", async (req, res) => {
    const { srcChain, dstChain, srcTokenAddress, dstTokenAddress, amount, walletAddress } = req.query
    console.log("Received params:", { srcChain, dstChain, srcTokenAddress, dstTokenAddress, amount, walletAddress })

    if (!srcChain || !dstChain || !srcTokenAddress || !dstTokenAddress || !amount || !walletAddress) {
        return res.status(400).json({ error: "Missing required query parameters" })
    }
    const { srcTokenData, dstTokenData } = await tokenData({
        srcChain: Number(srcChain) as SupportedChain,
        srcTokenAddress: String(srcTokenAddress),
        dstChain: Number(dstChain) as SupportedChain,
        dstTokenAddress: String(dstTokenAddress),
        amount: String(amount),
        walletAddress: String(walletAddress)
    })
    console.log(srcTokenData)
    const srcTokenPrice = srcTokenData.price || 0
    console.log("srcTokenPrice", srcTokenPrice)
    const dstTokenPrice = dstTokenData.price || 0
    console.log("dstTokenPrice", dstTokenPrice)
    const exchangeRate = srcTokenPrice / dstTokenPrice || 0
    console.log("exchangeRate", exchangeRate)

    // Use BigInt for multiplication with decimals
    const amountBigInt = BigInt(amount.toString())
    const srcTokenDecimals = BigInt(srcTokenData.decimals)
    const dstTokenDecimals = BigInt(dstTokenData.decimals)

    // For division, use Number
    const amountInSrcToken = Number(amountBigInt) / Math.pow(10, Number(srcTokenDecimals))
    console.log("amountInSrcToken", amountInSrcToken)

    // Calculate dstTokenAmount using BigInt for decimals
    const dstTokenAmount = (
        BigInt(Math.trunc(amountInSrcToken * exchangeRate * Math.pow(10, Number(dstTokenDecimals))))
    ).toString()
    console.log(dstTokenAmount)

    // Removed unused srcEscrowFactory variable and fixed ESCROW_FACTORY usage below

    const response: QuoterResponse = {
        quoteId: uuidv4(),
        srcTokenAmount: String(amount),
        dstTokenAmount: String(dstTokenAmount),
        srcEscrowFactory: (Number(srcChain) === NetworkEnum.SUI || Number(srcChain) === NetworkEnum.SOLANA)
            ? "0x0000000000000000000000000000000000000000"
            : ESCROW_FACTORY.hasOwnProperty(Number(srcChain))
                ? String(ESCROW_FACTORY[Number(srcChain) as keyof typeof ESCROW_FACTORY])
                : "0x0000000000000000000000000000000000000000",

        dstEscrowFactory: (Number(dstChain) === NetworkEnum.SUI || Number(dstChain) === NetworkEnum.SOLANA)
            ? "0x0000000000000000000000000000000000000000"
            : ESCROW_FACTORY.hasOwnProperty(Number(dstChain))
                ? String(ESCROW_FACTORY[Number(dstChain) as keyof typeof ESCROW_FACTORY])
                : "0x0000000000000000000000000000000000000000",
        recommendedPreset: PresetEnum.fast,
        presets: {
            fast: {
                auctionDuration: 180,
                startAuctionIn: 24,
                initialRateBump: 84909,
                auctionStartAmount: String(amount),
                startAmount: String(amount),
                auctionEndAmount: String(dstTokenAmount),
                costInDstToken: String(dstTokenAmount),
                points: [
                    {
                        delay: 120,
                        coefficient: 63932
                    },
                    {
                        delay: 60,
                        coefficient: 34485
                    }
                ],
                allowPartialFills: false,
                allowMultipleFills: false,
                gasCost: {
                    gasBumpEstimate: 0,
                    gasPriceEstimate: "0"
                },
                exclusiveResolver: null,
                secretsCount: 1
            },
            medium: {
                auctionDuration: 360,
                startAuctionIn: 24,
                initialRateBump: 84909,
                auctionStartAmount: String(amount),
                startAmount: String(amount),
                auctionEndAmount: String(dstTokenAmount),
                costInDstToken: String(dstTokenAmount),
                points: [
                    {
                        delay: 360,
                        coefficient: 34485
                    }
                ],

                allowMultipleFills: false,
                allowPartialFills: false,
                gasCost: {
                    gasBumpEstimate: 0,
                    gasPriceEstimate: "0"
                },
                exclusiveResolver: null,
                secretsCount: 1
            },
            slow: {
                auctionDuration: 600,
                startAuctionIn: 24,
                initialRateBump: 84909,
                auctionStartAmount: String(amount),
                startAmount: String(amount),
                auctionEndAmount: String(dstTokenAmount),
                costInDstToken: String(dstTokenAmount),
                points: [
                    {
                        delay: 600,
                        coefficient: 34485
                    }
                ],

                allowMultipleFills: false,
                allowPartialFills: false,
                gasCost: {
                    gasBumpEstimate: 10,
                    gasPriceEstimate: (BigInt(2e2) * BigInt(Math.pow(10, Number(srcTokenData.native.decimals)))).toString()
                },
                exclusiveResolver: null,
                secretsCount: 1
            }
        },
        prices: {
            usd: {
                srcToken: srcTokenPrice,
                dstToken: dstTokenPrice
            }
        },
        volume: {
            usd: {
                srcToken: srcTokenData.volume || "0",
                dstToken: dstTokenData.volume || "0"
            }
        },
        timeLocks: {
            srcWithdrawal: 0,
            srcPublicWithdrawal: 120,
            srcCancellation: 180,
            srcPublicCancellation: 240,
            dstWithdrawal: 0,
            dstPublicWithdrawal: 120,
            dstCancellation: 180,
        },
        srcSafetyDeposit: (BigInt(Math.trunc(0.001 * Math.pow(10, Number(srcTokenDecimals)))).toString()),
        dstSafetyDeposit: (BigInt(Math.trunc(0.001 * Math.pow(10, Number(dstTokenDecimals)))).toString()),
        autoK: 0,
        whitelist: [
            "0xD0725945859175dabd070855bC3F1c37a3aF605F"
        ],
    }
    console.log("Response:", response)
    res.json(response)
})

app.get("/", (req, res) => {
    res.send("Hello World!")
})

app.listen(port, () => {
    console.log(`Server is running at http://localhost:${port}`)
})