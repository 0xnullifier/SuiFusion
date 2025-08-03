# SuiFusion

Sui Fusion extends 1inch Fusion+ protocol to SUI. What sets SuiFusion apart from others is that it is fully working deployed with UI, has test for every case of the step for 1inch Fusion+ Swaps like private and public withdraws,cancel etc.. The move contracts respect HLTL logic and also the dutch auction extension is implemented. SuiFusion Extends the current `@1inch/cross-chain-sdk` and adds Sui Primitives to it. It comes with a fully working resolver backend, a relayer which communicates through a websocket stream. It is also shipped with a basic qouter.

## Move Contracts Architecture

## Changes made to `@1inch/cross-chain-sdk`

Changes made to sdk can be found at my fork [here]()

Here are the most meaningfull ones:

1. Adding a SuiAddress classe to the domains. This enables the already extendible sdk. what's unique about this class

## Getting Started
