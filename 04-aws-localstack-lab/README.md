# ☁️ Lab 04: Automatización IAM y Entorno Cloud Local con LocalStack

Procedimiento Operativo Estándar (SOP) para el despliegue de un entorno AWS simulado en local mediante **Docker Compose** y **LocalStack**, incorporando *Lifecycle Hooks* (`ready.d` y `shutdown.d`) para provisionar automáticamente identidades IAM, roles de servicio y auditorías de seguridad sin depender de un estado persistente.

---

## 🎯 1. Contexto y Motivación Técnica (El Porqué)

En entornos de aprendizaje y pruebas rápidas con **LocalStack** (versión *Freemium/Community*), el estado de los recursos IAM reside en memoria RAM (efímero): cada vez que se reinicia el contenedor o el equipo, los usuarios, grupos, políticas y roles desaparecen.

Para evitar reconfigurar manualmente toda la base de identidad al inicio de cada sesión de laboratorio y aplicar buenas prácticas de **AWS IAM (SAA-C03)** desde el primer minuto, se diseñó esta arquitectura automatizada bajo tres principios:

1. **Inmutabilidad y Reproducibilidad (*Bootstrap* automático):** Al pasar el contenedor a estado `READY`, un hook en Bash reconstruye desde cero la estructura base de IAM  y exporta las credenciales a un directorio local excluido de Git (`output/`).
2. **Separación de Privilegios (Admin vs. Test / Asunción de Roles):**
   - El usuario administrador (`aimenrial432`) hereda permisos totales a través de un **IAM Group** (`admin`), nunca mediante políticas directas sobre el usuario.
   - El usuario de pruebas (`aws_test`) no tiene permisos directos sobre servicios; en su lugar, tiene autorización mínima (`sts:AssumeRole`) para asumir **IAM Roles** temporales (`DemoRole*`), simulando exactamente cómo los servicios de AWS (como instancias EC2) consumen permisos sin exponer claves estáticas.
3. **Auditoría Continua al Cierre (*Teardown Hook*):** Antes de detener el contenedor de forma controlada, un hook de apagado (`shutdown.d`) extrae automáticamente el **IAM Credential Report** (CSV) y los datos de **IAM Access Advisor** (JSON) para auditar el uso real de credenciales y aplicar el principio de privilegio mínimo.

---

## 🏗️ 2. Arquitectura del Laboratorio

```text
04-aws-localstack-lab/
├── docker-compose.yml              # Orquestación del contenedor LocalStack y montaje de volúmenes
├── .env                            # Token de activación freemium (excluido de Git)
├── hooks/
│   ├── ready.d/
│   │   └── 01-init-iam.sh          # Provisionamiento automático al arrancar (Usuarios, Grupo, Roles)
│   └── shutdown.d/
│       └── 99-audit-iam.sh       # Extracción automática de reportes de auditoría al apagar
└── output/                         # Artefactos generados en ejecución (excluido de Git)
    ├── iam-credentials.json        # Access Keys generadas en el arranque
    ├── credential-report.csv       # Informe global de credenciales al cierre
    └── access-advisor-*.json       # Telemetría de servicios accedidos por usuario
```

### Flujo de Ejecución Automatizado

| Fase | Trigger | Script | Acciones Ejecutadas |
| :--- | :--- | :--- | :--- |
| **1. Arranque** | `ready.d` | `01-init-iam.sh` | • Limpia artefactos de sesiones previas en `output/`.<br>• Crea el grupo `admin` (`AdministratorAccess`), el alias `aimenrial-cloud-lab` y el usuario `aimenrial432`.<br>• Crea el usuario `aws_test` y genera las *Access Keys* de ambos en `output/iam-credentials.json`.<br>• Crea `DemoRoleForEC2` (`IAMReadOnlyAccess`) junto con su *Instance Profile* y autoriza a `aws_test` a asumir cualquier `DemoRole*`. |
| **2. Operación** | Manual (CLI) | `aws` / `awslocal` | • Pruebas de arquitectura, cambio de perfiles (`--profile`) y asunción temporal de roles mediante `sts:AssumeRole`. |
| **3. Apagado** | `shutdown.d` | `99-audit-iam.sh` | • Genera y decodifica (Base64 $\rightarrow$ CSV) el **IAM Credential Report**.<br>• Lanza trabajos asíncronos de **IAM Access Advisor** para `aimenrial432` y `aws_test` y guarda los resultados en JSON. |

---

## ⚙️ 3. Despliegue y Uso (SOP)

### Prerrequisitos
- **Docker Desktop** operativo.
- **AWS CLI v2** instalado en el host.
- Token gratuito de LocalStack (`LOCALSTACK_AUTH_TOKEN`) guardado en `.env`:

```env
LOCALSTACK_AUTH_TOKEN=ls-xxxxxxxxxxxxxxxxxxxx
```

### Levantar el Entorno

```powershell
cd 04-aws-localstack-lab
docker compose up -d
docker logs -f localstack-aws-lab
```

> **Validación:** Confirmar en los logs la aparición de `[INIT-IAM] Bootstrap IAM completado con exito.` y verificar que existe `output/iam-credentials.json`.

### Configurar Perfiles en AWS CLI (Host Windows)
Con las claves generadas en `output/iam-credentials.json`, registrar las identidades en `~/.aws/credentials`:

```powershell
aws configure --profile aimenrial432
aws configure --profile aws_test
```

### Detener el Entorno y Generar Auditoría

```powershell
docker compose down
```
> **Validación:** Al detener el contenedor de forma ordenada, comprobar en `output/` la creación de `credential-report.csv`, `access-advisor-aimenrial432.json` y `access-advisor-aws_test.json`.

---

## 🛠️ 4. Resolución de Incidencias Documentadas

- **Error `exit code 55 (License activation failed)` al arrancar:** Las imágenes recientes de LocalStack requieren `LOCALSTACK_AUTH_TOKEN` incluso en el plan gratuito (*Freemium*). Solucionado inyectando la variable desde `.env` en `docker-compose.yml`.
- **Error `/bin/bash^M: bad interpreter` en Windows:** Los scripts `.sh` editados en Windows contienen saltos de línea `CRLF`. Antes de montar los hooks, deben guardarse en codificación **UTF-8 sin BOM** y formato de línea Unix (**`LF`**).
- **Deprecación de `awslocal` en logs:** Para evitar el *overhead* visual de advertencias de deprecación en cada comando dentro de los hooks, se emplea un wrapper directo sobre `aws --endpoint-url=http://localhost:4566`.
