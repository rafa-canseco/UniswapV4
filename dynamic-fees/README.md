# 🔄 Dynamic Fees Hook

Vamos a construir un hook que ajuste los fees de la pool basándose en los precios del gas on-chain. 💵 En teoría, este ajuste debería hacer a una pool con fees dinámicos más competitiva que el resto de las pools en momentos de alta congestión en la red. 🚀

La idea es sencilla: ajustamos las swap fees, que van a depender de cuándo es en promedio el precio del gas on-chain.

## 🛠️ Diseño del mecanismo

Debemos hacer un diseño que lleve el record del movimiento promedio del precio del gas durante el tiempo. ⏳ Cuando el precio del gas sea más o menos igual al promedio, vamos a cobrar cierta cantidad de fees. Si el precio del gas es más allá del 10% por encima del promedio, vamos a cargar menos fees. Si el precio del gas es menos del 10% del promedio, vamos a cargar fees más altos.

Nuestro hook básicamente necesita hacer dos cosas:
- Llevar el record del promedio del precio del gas 🔍
- Para cada swap, ajustar dinámicamente las swap fees que se cobran. ⚙️

## 💰 Dynamic Fees en v4

Antes de escribir el código, repasemos algunos conceptos para entender cómo funcionan las dynamic fees y qué tanto necesitamos hacer. Recordemos que el ```PoolManager``` contiene un mapping de todas las pools, las cuales contienen el struct ```Pool.State```. Dentro del struct ```Pool.State```, existe el ```Slot0``` que se accede vía la función ```getSlot0()``` en el PoolManager si estamos usando el ```StateLibrary```.

Uno de los valores que es parte del ```Slot0``` es el ```lpFee```. Este valor representa los fees cobrados en cada swap. Normalmente, las pools definen un valor ```lpFee``` durante la inicialización del pool que no se puede cambiar. Un hook de fees dinámicos tiene la capacidad de hacer un update de este valor de manera customizada.

Hay dos maneras de hacerlo:
1) En caso de que los fees sean actualizados una vez por bloque o menos, usamos ```PoolManager.updateDynamicLpFee```. 
2) En casos en que los fees deban ser actualizados para cada swap, podemos regresar un valor ```OVERRIDE_FEE``` desde ```beforeSwap```.

Para el caso (1), el hook podría llamar a la función ```updateDynamicLPFee``` en el ```PoolManager``` en cualquier momento, pasando el ```PoolKey``` y el nuevo valor de la fee así ->

```bash
poolManager.updateDynamicLPFee(poolKey, NEW_FEES);
```

Vamos a ver la función a detalle:
```solidity
function updateDynamicSwapFee(PoolKey memory key, uint24 newDynamicSwapFee) external {
    if(!key.fee.isDynamicFee() || msg.sender != address(key.hooks)) revert UnauthorizedDynamicSwapFeeUpdate();
    newDynamicSwapFee.validate();
    PoolId id = key.toId();
    pools[id].setSwapFee(newDynamicSwapFee);
}
```

La función revisa:
- Que el pool sea un pool de fees dinámicos, esto se define al iniciar el pool y no se puede cambiar después. ❌
- También revisa que el que llama a la función sea el hook añadido a la pool. 🔗
- Luego el validate() se asegura que los nuevos fees no sean más grandes que ```MAX_SWAP_FEE```, que es 100%. 
- Si esto es correcto, el mapping de ```pools``` actualiza a los nuevos fees.

Para el caso (2), necesitamos usar ```beforeSwap```. Para esto, necesitamos devolver el valor de los fees junto con la flag marcada como 1, lo que va a indicar que ```OVERRIDE_FEE_FLAG``` está habilitado. 🆗

Entonces, para nuestro caso, ya que queremos cobrar fees diferentes para cada swap dependiendo del precio del gas, necesitamos regresar una fee que sobreescriba dentro de ```beforeSwap```, para que la fee se actualice antes de que el swap se ejecute. Y también necesitamos actualizar nuestro precio promedio del gas con ```afterSwap``` para los futuros swaps. 🔄

## 🛠️ Mismos pasos para instalar Foundry

```bash
# Iniciamos el proyecto nuevo
forge init dynamic-fees

# Entramos al proyecto e instalamos v4-periphery
cd dynamic-fees
forge install Uniswap/v4-periphery

# Hacemos los remappings
forge remappings > remappings.txt

# Borramos el contrato Counter.sol
rm ./**/Counter*.sol
```