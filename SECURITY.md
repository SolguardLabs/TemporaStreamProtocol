# Security Policy

## Modelo De Seguridad

TemporaStreamProtocol asume que los tokens configurados cumplen la interfaz
ERC-20 estandar y que los gestores de reserva son cuentas operativas de
confianza. Los pagadores solo arriesgan el principal que aprueban y bloquean al
crear streams. Los beneficiarios solo deben poder reclamar principal devengado
por ventanas activas y rendimiento atribuido por el indice del activo.

## Invariantes Esperadas

- El principal reclamado por un beneficiario no debe superar el principal
  devengado por el stream.
- El principal liberado para un pagador debe corresponder a principal no
  devengado.
- La reserva debe conservar accounting separado entre escrow, buffer de
  rendimiento y creditos liberados.
- Los streams cancelados o liquidados no deben generar nuevas obligaciones de
  principal.
- Las operaciones administrativas deben quedar restringidas al owner, gestores
  de reserva u operadores configurados.

## Validaciones Automatizadas

La suite publica cubre:

- creacion de streams y accounting de reserva;
- reclamaciones de principal por tiempo transcurrido;
- distribucion de rendimiento reportado;
- pausa y reanudacion con descuento de principal inactivo;
- retiro de principal liberado;
- cancelacion de streams cancelables;
- reclamacion combinada de principal y rendimiento.

Ejecutar:

```bash
forge test
```

## Gestion De Dependencias

El proyecto no depende de paquetes Solidity externos. Foundry instala el
compilador definido en `foundry.toml`. GitHub Actions se mantiene mediante
Dependabot.

## Alcance De Revision

Incluye todo `src/`, tests Foundry, scripts locales y workflow CI. Quedan fuera
integraciones con estrategias externas reales, oraculos de rendimiento y
adaptadores ERC-20 no estandar.

## Reporte Interno

Un reporte debe incluir descripcion, impacto economico, precondiciones,
transaccion o secuencia reproducible, activos afectados, severidad sugerida y
mitigacion propuesta.

