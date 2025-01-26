# Construyendo nuestro primer hook en Uniswap V4

## Que va a hacer nuestro hook?

Vamos a crear un hook que reparta ERC-20 tokens como puntos ante ciertos swaps
e interacciones con los pools de liquidez.

## Breakdown

Imaginemos que tenemos un token llamado  ```TOKEN``` Y queremos añadir un hook en los
pools ``` ETH <> TOKEN ```

Nuestra meta es incentivar a los swappers a comprar ```TOKEN``` en cambio de su 
``ETH``` y para los LPs, el que añada liquidez a nuestro pool.

Esta incetivzación va a suceder haciendo que el hook disperse un segundo token 
llamado ``` POINTS ``` cuando las acciones que queremos se realicen.

## Reglas simples y happy path

1.-Cuando un Swap ocurre que compra ```TOKEN```  en cambio de ```ETH```,vamos
a mintear ``` POINTS ``` equivalentes al 20% de la cantidad de cuanto
```ETH``` usó el el usuario en el swap.

2.-Cuando alguien agrega liquidez, vamos a mintear ``` POINTS ``` equivalentes al
a cuanto ```ETH``` es agregado al pool.


## Hooks disponibles 

```
beforeInitialize
afterInitialize

beforeAddLiquidity
beforeRemoveLiquidity
afterAddLiquidity
afterRemoveLiquidity

beforeSwap
afterSwap

beforeDonate
afterDonate

beforeSwapReturnDelta
afterSwapReturnDelta
afterAddLiquidityReturnDelta
afterRemoveLiquidityReturnDelta
```

Para el caso 1) podemos usar ```beforeSwap``` o ```afterSwap```
Para el caso 2) podemos usar ```beforeAddLiquidity``` o ```afterAddLiquidity```

Para decidir que opción tomamos veamos las funciones ->

```
beforeSwap(
	address sender, 
	PoolKey calldata key, 
	IPoolManager.SwapParams calldata params, 
	bytes calldata hookData
)

afterSwap(
	address sender,
	PoolKey calldata key, 
	IPoolManager.SwapParams calldata params, 
	BalanceDelta delta, 
	bytes calldata hookData
)
```

``` AfterSwap ``` tiene un argumento adicional -> ``` BalanceDelta delta ``` 🤔

## Los dos tipos de Swap -> podemos usar los SwapParams para decidir??

1.-**Exact input for Output** -> 
quiero cambiar exactamente 15 ```ETH``` por su alguna cantidad de ```TOKEN```

2.-**Exact output for Input** ->
Quiero recibir exactamente 15 ```TOKEN``` por y puedo pagar hasta 3  ```ETH```
por ellos

Escogemos esto basado en el parámetro ``` amountSpecified ``` en el struct 
``` SwapParams ``` -> Los valores de Uniswap son representadas siempre
desde la perspectiva del usuario, por lo tanto tenemos dos opciones:

1.-Especificar un valor negativo para ``` amountSpecified ```.
Un valor negativo significa ***"Dinero saliendo de la billetera del usuario"***
Esto significa un "Exact Input for Output" swap.
Estamos espeficando exactamente cuando dinero va a salir de la billetera del usuario
esperando una cantidad calculada de output tokens.

2.-Especificar un valor positivo para ``` amountSpecified ```.
Un valor positivo significa ***Dinero entrando en la billetera del usuario***.
Esto significa un "Exact Output for Input" swap.
Estamos espeficando exactamente cuando dinero va a entrar en la billetera del usuario
esperando una cantidad calculada de input tokens.

Entonces como un swap ``` ETH -> TOKEN ```  puede pasar de ambas maneras (exact input for output, o 
exact output for input) no siempre vamos a saber cuanto `` ETH ```  realmente se gasta.
Lo vamos a saber cuando se espefica el ``` ETH ``` como un input exacto, pero no
cuando se especifica cuanto ``` TOKEN ``` se espera como un output exacto. por lo tanto no
podemos usar ``` SwapParams```

## Escogiendo el hook correcto

Dado que no siempre vamos a saber cuanto ``` ETH ``` se gasta, el hook ``` beforeSwap ```
no podemos usarlo, sin embargo el valor ``` BalanceDelta delta ``` dentro de ``` afterSwap ```
nos va a dar el valor exacto de cuanto ``` ETH ``` es gastado por cuanto `` TOKEN ```
dado que en un punto ya hicimos calculos para saberlos.

Entonces para el caso 1) podemos usar ``` afterSwap ``` y para el caso 2) podemos usar
``` afterAddLiquidity ``` por la siguiente razón:

el usuario va a mandar alguna cantidad de ``` ETH ```entonces cuando 
el contrato calcula el ratio correcto de ``` ETH <> TOKEN ```
requerido para agregar liquidez, puede ser que el usuario haya mandado ``` ETH ```
de mas, entonces debemos regresarle una cantidad al usuario.

Entonces para saber con confianza cuando ``` ETH ``` es agregado a la pool, podemos usar
el hook ``` afterAddLiquidity ``` porque continen el valor ``` BalanceDelta delta ```
que nos va a dar esa información exacta.

## Instalación 

Vamos a crear proyecto de foundry 

en caso de que no lo tengas instalado -> https://book.getfoundry.sh/getting-started/installation

Una vez que Foundry este instalado, ejecutamos para crear nuestro proyecto:

``` 
forge init points-hook 
```

entramos al directorio del proyecto con 

``` 
cd points-hook 
```

y luego instalamos los contratos de  Uniswap ```v4-periphery``` como una dependencia:

``` 
forge install https://github.com/Uniswap/v4-periphery 
```

Vamos a crear remappings para acortar nuestras importaciones

``` 
forge remappings > remappings.txt 
```

y finalmente vamos a elimar el template del contrato ``` Counter ``` que viene pre instalado

``` 
rm ./**/Counter*.sol 

```

Como la v4 utiliza transient storage, necestamos una versión mas actualizada
de Solidity mas allá de  >= 0.8.24, esto lo hacemos en el ``` foundry.toml ```
```
# foundry.toml

solc_version = '0.8.26'
evm_version = "cancun"
optimizer_runs = 800
via_ir = false
ffi = true
```