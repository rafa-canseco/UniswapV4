/// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract PointsHook is BaseHook, ERC20 {
    // Usamos BalanceDeltaLibrary para añadir
    // funciones que nos ayuden sobre los tipos de datos en BalanceDelta
    using BalanceDeltaLibrary for BalanceDelta;
    
    //Inicializamos BaseHook y ERC20
    constructor(
        IPoolManager _manager,
        string memory _name,
        string memory _symbol
    ) BaseHook(_manager) ERC20(_name, _symbol, 18) {}
    
    //Necesitamos especificar que hooks vamos a usar retorneado
    //el booleano true
    function getHookPermissions()
          public
          pure
          override
          returns (Hooks.Permissions memory)
      {
          return
              Hooks.Permissions({
                  beforeInitialize: false,
                  afterInitialize: false,
                  beforeAddLiquidity: false,
                  beforeRemoveLiquidity: false,
                  afterAddLiquidity: true,
                  afterRemoveLiquidity: false,
                  beforeSwap: false,
                  afterSwap: true,
                  beforeDonate: false,
                  afterDonate: false,
                  beforeSwapReturnDelta: false,
                  afterSwapReturnDelta: false,
                  afterAddLiquidityReturnDelta: false,
                  afterRemoveLiquidityReturnDelta: false
              });
      }
    
    //Nota:la función regresa su mismo selector al final, esto debe ser
    // true siempre, si otra cosa es regresa la llamda al hook no es éxitosa
    // el segundo argumento al momento puede ser 0 sin caudar problemas, este argumento
    // lo vamos a estudiar cuando llegemos a NoOp hooks.
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, int128) {
        //Si no es un pool ETH-TOKEN con este hook añadido, lo ignoramos
        if (!key.currency0.isAddressZero()) return ( this.afterSwap.selector,0);
        
        //Solo minteamos puntos si el usuario esta comprando TOKEN con ETH
        if (!swapParams.zeroForOne) return (this.afterSwap.selector,0);
        
        //Minteamos puntos igual al 20% de la cantidad de ETH que se gasto
        //desde que es un sea ZeroForOne:
        //if amountSpecified < 0:
        //    este sería un swap "exact input for output"
        //    la cantidad de ETH que se gastó es igual a amountSpecified
        // if amountSpecified > 0:
        //    este sería un swap "exact output for input"
        //      la cantidad de ETH que se gasta es igual a BalanceDelta.amount0()
        
        
        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointsForSwap = ethSpendAmount / 5;
        
        //Minteamos los puntos
        
        _assignPoints(hookData, pointsForSwap);
        
        return (this.afterSwap.selector, 0);
    }

    //Nota:la función regresa su mismo selector al final, esto debe ser
    // true siempre, si otra cosa es regresa la llamda al hook no es éxitosa
    // el segundo argumento al momento puede ser 0 sin caudar problemas, este argumento
    // lo vamos a estudiar cuando llegemos a NoOp hooks.
    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
	BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        //Si no es un pool ETH-TOKEN con este hook añadido, lo ignoramos
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, delta);
        
        
        // Minteamos los puntos equivalentes a cuanto ETH se agrega en liquidez
        uint256 pointsForAddingLiquidity = uint256(int256(-delta.amount0()));
        
        //Mint the points
        _assignPoints(hookData, pointsForAddingLiquidity);
        
        return (this.afterAddLiquidity.selector, delta);
    }

    
    function _assignPoints(bytes calldata HookData, uint256 points) internal {
        
        //si no se pasa hookData, no se asignan puntos a nadie
        if (HookData.length == 0) return;
        
        //Extraemos el address del usuario del hookData
        address user = abi.decode(HookData,(address));
        
        //Si hay hook data, pero no en el formato que esperamos y el address
        //del usuario es 0, nadie consigue puntos
        if (user == address(0)) return;
        
        //Minteamos los puntos
        _mint(user,points);
    }
}
