# check_3com_4210g
Plugin de monitorización de switches 3Com 4210G vía Web para Nagios

## Uso
```
Uso: check_3com_4210g.sh -H <host> -u <usuario> -p <contraseña> -t tipo [-w <temp_warn>] [-c <temp_crit>] [-l <lang>]

Opciones:
  -H  IP o hostname del switch (requerido)
  -u  Usuario de acceso web (requerido)
  -p  Contraseña (requerido)
  -w  Umbral WARNING temperatura (°C, default: 50)
  -c  Umbral CRITICAL temperatura (°C, default: 60)
  -t  Tipo de entidad a monitorear: PSU, FAN o TEMP (requerido)
  -l  Idioma (default: 0)
  -h  Mostrar ayuda
```
