# TemporaStreamProtocol

![banner](./assets/banner.png)

TemporaStreamProtocol es un protocolo de pagos continuos respaldados por
depositos productivos. Un pagador bloquea principal para un beneficiario y el
derecho de cobro se acumula segundo a segundo durante la ventana activa del
stream. El principal no vencido permanece dentro de una reserva productiva que
mantiene un indice de rendimiento por activo.

## Componentes

- `TemporaStreamProtocol`: coordinador de streams, pausas, reanudaciones,
  reclamaciones y reservas por activo.
- `StrategyReserve`: custodia interna de principal, buffer de rendimiento y
  creditos liberados para pagadores.
- `YieldIndex`: acumulador temporal usado para atribuir rendimiento a streams
  abiertos.
- `PrincipalLedger`, `ReserveMath` y `StreamRiskModel`: librerias de consulta,
  salud de reservas y scoring operativo.
- `TemporaLens`: contrato de lectura para agregados de cuenta y reserva.
- `MockERC20`: activo de pruebas para la suite Foundry.

## Requisitos

- Foundry estable instalado y disponible en `PATH`.
- Solidity `0.8.26`, configurado en `foundry.toml`.

## Uso Local

```bash
forge build
forge test
```

Los scripts reproducibles son:

```bash
bash scripts/tests.sh
bash scripts/ci.sh
```

En Windows tambien hay wrappers equivalentes:

```powershell
./scripts/tests.ps1
./scripts/ci.ps1
```

## Flujo Del Protocolo

1. El gestor habilita una reserva para un token y define su tasa de indice.
2. El pagador aprueba el token y crea un stream con beneficiario, tasa por
   segundo, inicio y vencimiento.
3. El beneficiario reclama principal acumulado durante ventanas activas.
4. Los participantes pueden pausar y reanudar streams cuando existe una ventana
   operativa sin servicio.
5. El principal no devengado se libera como credito retirable para el pagador.
6. El rendimiento reportado por la reserva se distribuye mediante el indice del
   activo.

## CI

GitHub Actions ejecuta:

- `forge fmt --check`
- `forge build`
- `forge test`

Dependabot cubre las acciones de GitHub usadas por el workflow.

## Estructura

```text
src/
  access/
  accounting/
  core/
  interfaces/
  lens/
  libraries/
  mocks/
  policy/
  settlement/
  tokens/
tests/
scripts/
.github/
.vscode/
```

## Estado

Proyecto de auditoria local con contratos autocontenidos, tests publicos de
flujos principales y configuracion reproducible para Foundry.
