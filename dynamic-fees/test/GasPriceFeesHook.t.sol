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
import {SwapParams,ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

contract TestGasPriceFeesHook is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    GasPriceFeesHook hook;

    function setUp() public {
        // Desplegar uni v4
        deployFreshManagerAndRouters();

        // Desplegar, mintear tokens y aprovar los contratos periféricos
        // para dos tokens
        deployMintAndApprove2Currencies();

        // Desplegar nuestro hook con las flags apropiadas
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
            )
        );


        // Setear el precio del gas = 10 wei y desplegar nuestro hook
        vm.txGasPrice(10 gwei); // Establece el gas price para la transacción actual
        deployCodeTo("GasPriceFeesHook",
            abi.encode(manager),
            hookAddress);
        hook = GasPriceFeesHook(hookAddress);

        // Inicializar el pool
        (key, ) = initPool(
            currency0,                     // 1. Currency
            currency1,                     // 2. Currency
            hook,                          // 3. IHooks
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // 4. uint24 (fee)
            int24(60),                     // 5. int24 (tickSpacing) <-- AÑADIR ESTO
            SQRT_PRICE_1_1                 // 6. uint160 (sqrtPriceX96) <-- MOVER ESTO AQUÍ
            // ZERO_BYTES                  // <-- ELIMINAR ESTO
        );

        // Agregamos liquidez
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

    }

    function test_feeUpdatesWithGasPrice() public {
        /// Seteamos nuestros parámetros para el swap
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -0.00001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });


        // El precio actual es 10 gwei
        // el promedio debería de ser 10

        uint128 gasPrice = uint128(tx.gasprice);
        uint128 movingAverageGasPrice = hook.movingAverageGasPrice();
        uint104 movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(gasPrice, 10 gwei);
        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 1);

        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------

        // 1. Haz un swap a gas price = 10 
        // Esto debería usar solo `BASE_FEE` ya que el precio del gas es el mismo que el promedio actual
        uint256 balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        uint256 balanceOfToken1After = currency1.balanceOfSelf();
        uint256 outputFromBaseFeeSwap = balanceOfToken1After -
            balanceOfToken1Before;

        assertGt(balanceOfToken1After, balanceOfToken1Before);

        // Nuestro promedio móvil no debería haber cambiado
        // solo el conteo debería haber incrementado
        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 2);

        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------

        // 2. Realiza un swap a un gas price menor = 4 gwei
        // Esto debería tener tarifas de transacción más altas
        vm.txGasPrice(4 gwei);
        balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        balanceOfToken1After = currency1.balanceOfSelf();

        uint256 outputFromIncreasedFeeSwap = balanceOfToken1After -
            balanceOfToken1Before;

        assertGt(balanceOfToken1After, balanceOfToken1Before);

        // Nuestro promedio móvil ahora debería ser (10 + 10 + 4) / 3 = 8 Gwei
        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 8 gwei);
        assertEq(movingAverageGasPriceCount, 3);

        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------

        // 3. Realiza un swap a un gas price más alto = 12 gwei
        // Esto debería tener tarifas de transacción más bajas
        vm.txGasPrice(12 gwei);
        balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        balanceOfToken1After = currency1.balanceOfSelf();

        uint outputFromDecreasedFeeSwap = balanceOfToken1After -
            balanceOfToken1Before;

        assertGt(balanceOfToken1After, balanceOfToken1Before);

        // Nuestro promedio móvil ahora debería ser (10 + 10 + 4 + 12) / 4 = 9 Gwei
        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();

        assertEq(movingAverageGasPrice, 9 gwei);
        assertEq(movingAverageGasPriceCount, 4);

        // ------

        // 4. Verifica todos los montos de salida

        console.log("Base Fee Output", outputFromBaseFeeSwap);
        console.log("Increased Fee Output", outputFromIncreasedFeeSwap);
        console.log("Decreased Fee Output", outputFromDecreasedFeeSwap);

        assertGt(outputFromDecreasedFeeSwap, outputFromBaseFeeSwap);
        assertGt(outputFromBaseFeeSwap, outputFromIncreasedFeeSwap);
    }
}