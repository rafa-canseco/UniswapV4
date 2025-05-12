// SPDX-License-Identifier:  MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency,CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId,PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {GasPriceFeesHook} from "../src/GasPriceFeesHook.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";

contract TestGasPriceFeesHook is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    
    GasPriceFeesHook hook;
    
    function setUp() public {
        // Deployar uni v4
        deployFreshManagerAndRouters();
        
        //Deployar, mintear tokens y aprovar los contratos periféricos
        //para dos tokens
        deployMintAndApprove2Currencies();
        
        //Deployar nuestro hook con las proper flags
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
            )
        );
        
        
        //setear el precio del gas = 10 wei  y deployar nuestro hook
        vm.txGasPrice(10 gwei);
        deployCodeTo("GasPricesHook",
            abi.encode(manager),
            hookAddress);
        hook = GasPriceFeesHook(hookAddress);
        
        // Inicializar la Pool
        (key,) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
        
        //Agregamos liquidez
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

    }
}