# Setup Fedora35 (WSL) — entorno de ejecución y parches MXNet

Estado: **APLICADO Y VALIDADO** (2026-06-20). Los 5 parches `.pm` del MXNet_patches.zip
actualizado fueron instalados sobre los originales, con respaldo previo. `AI::MXNet` carga sin
errores y las operaciones de NDArray (incluido `slice`) funcionan correctamente.

## Entorno

- WSL distro `Fedora35` (EOL desde dic 2022; mirrors en `archives.fedoraproject.org`).
- Usuario root por defecto; no se requiere `sudo`.
- GUI vía WSLg (Tk funciona; `DISPLAY` se configura solo).
- Perl 5.34. Módulos AI::MXNet bajo `/usr/local/share/perl5/5.34/AI/MXNet/`.
- Copia del repo en Fedora35: `~/Documents/ProyectoIA/ProyectoIAAA` (sync con GitHub).

## Respaldo de los .pm originales

Antes de sobrescribir, se respaldaron los 5 archivos `.pm` originales con su estructura de
directorios en:

```
/opt/src/mxnet_pm_backup_20260620/
  AI/MXNet/NDArray.pm          (51702 bytes, 2022-06-10)
  AI/MXNet/Base.pm             (13025 bytes, 2022-11-07)
  AI/MXNet/NS.pm               ( 2981 bytes, 2025-05-23)
  AI/MXNet/NDArray/Slice.pm    ( 5159 bytes, 2022-06-07)
  AI/MXNet/NDArray/Base.pm     ( 6823 bytes, 2022-04-25)
```

Para revertir: `cp -p /opt/src/mxnet_pm_backup_20260620/AI/MXNet/*.pm /usr/local/share/perl5/5.34/AI/MXNet/` y `cp -p /opt/src/mxnet_pm_backup_20260620/AI/MXNet/NDArray/*.pm /usr/local/share/perl5/5.34/AI/MXNet/NDArray/`.

## Parche MXNet — aplicado el 2026-06-20

Se actualizaron 5 archivos `.pm` en dos subcarpetas:
- 1ª subcarpeta: `AI/MXNet/NDArray.pm`, `AI/MXNet/Base.pm`, `AI/MXNet/NS.pm`
- 2ª subcarpeta: `AI/MXNet/NDArray/Slice.pm`, `AI/MXNet/NDArray/Base.pm`

Procedimiento ejecutado:

```bash
# 1) Eliminar la carpeta de parches vieja
rm -rf /opt/src/MXNet_patches/

# 2) Descargar el MXNet_patches.zip ACTUALIZADO desde el SharePoint del profesor:
#    https://epnecuador-my.sharepoint.com/:f:/g/personal/josafa_aguiar_epn_edu_ec/IgCcdW-3Z0eIQ5IA1u1W8nRUAW2E0aBEreGBWePpD9tRBS0?e=chQgw7
#    (descargar a ~/Downloads/MXNet_patches.zip)

# 3) Copiar y descomprimir en /opt/src
cp ~/Downloads/MXNet_patches.zip /opt/src/
unzip /opt/src/MXNet_patches.zip   # (ejecutar dentro de /opt/src)

# 4) Primera subcarpeta
sudo cp -p /opt/src/MXNet_patches/AI/MXNet/NDArray.pm /usr/local/share/perl5/5.34/AI/MXNet/NDArray.pm
sudo cp -p /opt/src/MXNet_patches/AI/MXNet/Base.pm    /usr/local/share/perl5/5.34/AI/MXNet/Base.pm
sudo cp -p /opt/src/MXNet_patches/AI/MXNet/NS.pm      /usr/local/share/perl5/5.34/AI/MXNet/NS.pm

# 5) Segunda subcarpeta
sudo cp -p /opt/src/MXNet_patches/AI/MXNet/NDArray/Slice.pm /usr/local/share/perl5/5.34/AI/MXNet/NDArray/Slice.pm
sudo cp -p /opt/src/MXNet_patches/AI/MXNet/NDArray/Base.pm  /usr/local/share/perl5/5.34/AI/MXNet/NDArray/Base.pm
```

Archivos parchados (fechas del zip actualizado, junio 2026):

| Archivo | Tamaño antes | Tamaño después |
|---------|-------------|----------------|
| `NDArray.pm` | 51702 | 79505 |
| `Base.pm` | 13025 | 13054 |
| `NS.pm` | 2981 | 8842 |
| `NDArray/Slice.pm` | 5159 | 9921 |
| `NDArray/Base.pm` | 6823 | 12458 |

El zip también incluía archivos extra no copiados: `Types.pm`, `Gluon/Block.pm`,
`Gluon/NN/BasicLayers.pm`, `python/mxnet/gluon/block.py`. Quedan disponibles en
`/opt/src/MXNet_patches/` por si el profesor indica instalarlos.

## Validación (2026-06-20)

```bash
# Carga sin error:
perl -MAI::MXNet -e 'print "MXNet OK\n"'          # → MXNet OK

# NDArray básico:
perl -MAI::MXNet -e 'my $a = AI::MXNet::NDArray->ones([3,3]); print join(" ", @{$a->shape}), "\n";'  # → 3 3

# Slice (operación clave para Viterbi tensorial):
perl -MAI::MXNet -e 'my $a = AI::MXNet::NDArray->array([1,2,3,4,5,6]); my $s = $a->slice([0,2,4]); print "Slice OK\n";'  # → Slice OK
```

Pendiente: comparar las salidas D, E, OPT del ejemplo de referencia contra
`docs/material_profesor/Viterbi-tensorial-v0.3_ejercicio.docx`.

## Notas
- El parcheo afecta archivos del sistema (`/usr/local/share/perl5/...`). El respaldo en
  `/opt/src/mxnet_pm_backup_20260620/` permite revertir.
- MXNet Python (v1.9.1, CPU) también funciona pero **sin GPU** (`USE_CUDA=0` al compilar). No
  afecta al proyecto (que usa `AI::MXNet` Perl, no Python MXNet).
- No se requiere para Fase 2 (SMC/Liquidez/Replay/UI son Perl/Tk puro). Sí para Fase 3 (HMM/
  Viterbi tensorial con tensores MXNet).
