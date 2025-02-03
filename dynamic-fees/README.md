# Dynami Fees hook

Vamos a construir un hook que ajuste los fees de la pool basándise en los precios del gas on chain.
En teoría, este ajuste debería hacer a una pool con fees dinámicos mas competitiva que el resto de las
pools en momento s de alta congestión en una red.

La idea es sencilla, ajustamos las swap fees que se cargan van a depender de cuando es en promedio
el precio del gas on chain.

## Diseño del mecanismo

Debemos hacer un diseño que lleve el record del movimiento promedio del precio del gas durante el tiempo.
Cuando el precio del gas sea mas o menos igual al promedio, vamos a cobrar cierta cantidad de fees. Si
el precio del gas es mas allá del 10% arriba del promedio, vamos a cargar menos fees. Si el precio del gas
es menos que el 10% del promedio vamos a cargar fees mas altos.

Nuestro hook basicamente necesita hacer dos cosas:
- Llevasr el record del promedio de del precio del gas
- Para cada swap, ajustar dinámicamente las swap fees que se cobran.

## Dynamic Fees en v4

Antes de escribir el código repasemos algunos conceptos para entender como funcionan las dynamic fees y
que tanto necesitamos hacer.
Recordemos que el ```PoolManager``` contiene un mapping de todas las pools, las cuales contienen el struct
```Pool.State```. Dentro del struc ```Pool.State```, existe el ```Slot0``` que se accede via la función
```getSlot0()``` en el PoolManager si estamos usando el ```StateLibrary```.

Uno de los valores que es parte del ```Slot0``` es el ```lpFee```. Este valor representa los valores cobrados 
en cada swap.Normalmente, las pools definen un valor ```lpFee``` durante la inicialización del pool que no
se puede cambiar. Un hook de fees dinámicas tiene la capacidad de hacer un update de este valor de manera
customizada.

Hay dos maneras de hacerlo:
1)En caso de que las fees sean actualizadas una vez por bloque o menor a eso, usamos ```PoolManager.updateDynamicLpFee```
2)En casos en que las fees deban ser actualizadas para cada swap, podemos regresar un valor ```OVERRIDE_FEE``` desde ```beforeSwap```.

Para el caso (1), el hook podría llamar a la función ```updateDynamicLPFee``` en el ```PoolManager``` en cualquier
momento, pasando el ```PoolKey``` y el nuevo valor de la fee así ->

```bash
poolManager.updateDynamicLPFee(poolKey, NEW_FEES);
```

Vamos a ver la función a detalle:
```bash
function updateDynamicSwapFee(PoolKey memory key, uint24 newDynamicSwapFee) external {
    if(!key.fee.isDynamicFee() || msg.sender != address(key.hooks)) revert UnathorizedDynamicSwapFeeUpdate();
    newDynamicSwapFee.validate();
    PoolId id = key.toId();
    pools[id].setSwapFee(newDynamicSwapFee);
}
```

La función revisa:
-Que el pool sea un pool de fees dinámicos,esto se define al iniciar el pool y no se puede cambiar después.
-También revisa que el que llama a la función sea el hook añadido a la pool.
-Luego el validate() se asegura que las nuevas fees no sean mas grandes que ```MAX_SWAP_FEE``` que es 100%
-Si esto es correcto mapping de ```pools``` actualiza a las nuevas fees.

Para el caso(2), necesitamos usar ```beforeSwap```.Para esto necesitamos devolver el valor de las fees junto con la 
flag marcada como 1, lo que va a indicar que ```OVERRIDE_FEE_FLAG``` esta habilitado.

Entonces para nuestro caso, ya que queremos cobrar fees diferentes para cada swap dependiendo del precio del gas
,necesitamos regrarar una fee que sobreescriba dentro de ```beforeSwap``` , para que la fee se actualice antes
de que el swap se ejecute. Y también necesitamos actualizar nuestro precio promedio del gas con ```afterSwap```
para los futuros swaps.

## Mismos pasos para instalar Foundry

```bash
# Iniciamos el proyecto nuevo
forge init dynamic-fees

# Entramos al proyecto e instalamos v4-periphery
cd dynamic-fees
forge install Uniswap/v4-periphery

# Hacemos los remappings
forge remappings > remappings.txt

# borramos el contrato Counter.sol
rm ./**/Counter*.sol

```