// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency,CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import "forge-std/console.sol";
import {PointsHook} from "../src/PointsHook.sol";

contract TestPointsHook is Test, Deployers {
    using CurrencyLibrary for Currency;
    
    MockERC20 token; //Nuestro token que se va a usar en la pool ETH-TOKEN
    
    //Los tokens nativos son representados por el address(0);
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;
    
    PointsHook hook;
    
    //Hacemos nuestro set up con los deploys y movimientos necesarios
    function setUp() public {
        //Deployar los contratos de PoolManager and Router
        deployFreshManagerAndRouters();
        
        //Deployar nuestro contrato TOKEN
        token = new MockERC20("Test Token","Test",18);
        tokenCurrency = Currency.wrap(address(token));
        
        //Mintear algunos tokens para nosotros
        token.mint(address(this), 1000 ether);
        
        //Deployar el hook a un address que tenga las flags adecuadas
        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        deployCodeTo(
            "PointsHook.sol",
            abi.encode(manager, "Points Token", "TEST_POINTS"),
            address(flags)
        );
        
        //Deployar nuestrp hook
        hook = PointsHook(address(flags));
        
        //Aprovar nuestro TOKEN para que sea gastado por el swap router
        // y modificar el liquidity router
        // estas variables vienen del contrato `Deployers`
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        
        //Initcializamos la pool
        (key,) = initPool(
            ethCurrency, //Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, //Contrato de nuestro hook
            3000, //Swap fees
            SQRT_PRICE_1_1 // Valor inicial Sqrt(P) = 1
        );
    }
    
    //Tests a realizarse 
    //Add liquidity + Swap -> Checar que los puntos sean correctos
    function test_addLiquidityAndSwap() public {
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this));
        
        //Seteamos el address del usuario en el hook data
        bytes memory  hookData = abi.encode(address(this));
        
        //seteamos lo tick limites de nuestra posición
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        
        //Agregamos la liquidez a la pool
        uint256 ethToAdd = 0.1 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            ethToAdd
        );
        uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            liquidityDelta
        );
        
        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper:60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            hookData
        );
        uint256 pointsBalanceAfterAddLiquidity =
        hook.balanceOf(address(this));
        
        //nos aseguramos que obtivumos los puntos equivalentes
        assertApproxEqAbs(
            pointsBalanceAfterAddLiquidity - pointsBalanceOriginal,
            0.1 ether,
            0.001 ether // Margen de error para la pérdida de precisión
        );
        
        //Swap
        //Vamos a swapear 0.001 ether por TOKENS
        //Deberíamos obtener el 20% de 0.001 * 10**18 POINTS
        // = 2 * 10**14
        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, //Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );
        
        //nos aseguramos de obtener los puntos por el swap
        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this));
        assertEq(
            pointsBalanceAfterSwap - pointsBalanceAfterAddLiquidity,
            2 * 10 **14
        );
    }
}