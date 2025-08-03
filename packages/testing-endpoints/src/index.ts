import { evmToSuiMain } from "./evmToSui";
import { suiToEvmMain } from "./suiToEvm";

const direction = process.argv[2];
console.log(`Running in direction: ${direction}`);
if (direction === "evm-to-sui") {
    evmToSuiMain();
} else if (direction === "sui-to-evm") {
    suiToEvmMain();
} else {
    console.log("Usage: node index.js <evm-to-sui|sui-to-evm> [args]");
}
