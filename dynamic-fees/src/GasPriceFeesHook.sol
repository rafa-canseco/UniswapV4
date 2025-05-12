// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

contract GasPriceFeesHook is BaseHook {
    using LPFeeLibrary  for uint24;

    //Esta variable va a llevar el precio promedio del gas
    uint128 public movingAverageGasPrice;

    //Necesitamos llevar un conteo de cuantas veces se cambia el
    //precio promedio, vamos a utilizar este dato como denominador
    //en nuestra formula para calcular la media móvil del precio promedio
    uint104 public movingAverageGasPriceCount;

    //La base inicial de las fees que vamos a cobrar
    uint24 public constant BASE_FEE = 5000; // 0.5%

    error MustUseDynamicFee();

    //Iniciamos el contrato BaseHook padre en el constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        updateMovingAverage();
    }

    // Hacemos una función que va a sobreescribir en el BaseHook para
    // que el PoolManager sepa que Hooks están implementados
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return 
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeInitialize( 
        address,
        PoolKey calldata key,
        uint160
        ) internal override returns (bytes4) {
            //La funcion `.isDynamicFee()` viene de usar 
            //la librería `SwapFeeLibrary` para `uint24`
            if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
            return this.beforeInitialize.selector;
        }

    function _beforeSwap (
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    )
    internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint24 fee = getFee();
        //Si quisieramos hacer un update de las fees del LP para una mayor duración que cada vez que 
        //haya un swap -> poolManager.updateDynamicLPFee(key,fee);

        //Para hacer un override del fee por swap
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeWithFlag);
    }

    function _afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta, 
        bytes calldata
    ) internal override returns (bytes4, int128) {
        updateMovingAverage();
        return (this.afterSwap.selector, 0);
    }

    //Función para actualizar nuestro precio promedio del gas
    function updateMovingAverage() internal {
        uint128 gasPrice = uint128(tx.gasprice);

        // Nuevo promedio = ((Viejo Promedio * # txns tracked) + Precio actual del gas) / (# de txns tracked +1)
        movingAverageGasPrice = ((movingAverageGasPrice * 
            movingAverageGasPriceCount) + gasPrice) /
            (movingAverageGasPriceCount + 1);

        movingAverageGasPriceCount++;
    }

    function getFee() internal view returns (uint24) {
        uint128 gasPrice = uint128(tx.gasprice);

        //Si el gasPrice > movingAverageGasPrice * 1.1,
        //entonces dividimos las fees a la mitad
        if (gasPrice > (movingAverageGasPrice * 11) / 10) {
            return BASE_FEE / 2;
        }

        //Si el gasPrice < movingAverageGasPrice * 0.9,
        //cobramos el doble de fees
        if (gasPrice < (movingAverageGasPrice * 9) / 10) {
            return BASE_FEE * 2;
        } 

        return BASE_FEE;
    }
}