# Integración de pagadores y beneficiarios

La creación requiere dirección del token, beneficiario, inicio, vencimiento, tasa, reserva mínima, permiso de cancelación y hash de metadatos. El pagador aprueba primero el principal calculado y llama `createStream`. El beneficiario consulta `claimablePrincipal` y `claimableYield` antes de cada reclamación.

```mermaid
sequenceDiagram
    participant P as Pagador
    participant C as Cliente
    participant T as Token ERC-20
    participant S as TemporaStreamProtocol
    participant B as Beneficiario
    P->>C: Condiciones del stream
    C-->>P: Principal = tasa × duración
    P->>T: approve(protocolo, principal)
    P->>S: createStream(request)
    S-->>C: streamId y evento
    B->>S: claimablePrincipal(streamId)
    B->>S: claimPrincipal(streamId)
```

`TemporaScheduleLens.project(protocol, streamId, horizonSeconds)` acepta un horizonte de 1 segundo a 30 días. Devuelve el estado, ventana efectiva, principal incremental estimado, reclamable actual y saldo remanente. Una pausa devuelve incremento cero; la proyección no ejecuta pagos ni anticipa futuras decisiones de participantes.

Errores operativos: aprobación insuficiente, token no configurado, beneficiario inválido, duración fuera de política, estado incompatible o reserva no habilitada. Tras una reversión, reconsultar `streamOf` y la reserva antes de reintentar.
