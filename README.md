# disk-led

Bash script to read and control disk bay LEDs (locate / fault) via sysfs enclosure slots.

## Requirements

- Linux with SES enclosure support (`/sys/.../enclosure/*/locate`)
- `smartctl` (smartmontools) for verbose status
- root privileges

## Usage

```bash
./led.sh                  # status (default)
./led.sh status           # status
./led.sh status -v        # status + model, serial, capacity (slower, uses smartctl)
./led.sh status -vv       # verbose + sas_address
./led.sh statusShort      # short status: main_sg:slot|block_device|locate|fault
./led.sh help
```

## LED control

```bash
./led.sh ident /dev/sdX     # turn on locate LED by block device
./led.sh ident /dev/sgX:Y   # turn on locate LED by enclosure slot
./led.sh fail  /dev/sdX     # turn on fault LED
./led.sh fail  /dev/sgX:Y
./led.sh clean /dev/sdX     # turn off both LEDs for a device
./led.sh clean /dev/sgX:Y
./led.sh clean all          # turn off all LEDs
```

## Status output

```
#main_sg:slot | status | device_block | device_block_parts | led
/dev/sg2:0    | OK     | sda          | sda1 sda2          | ident:fail 0:0
```

- `ident` is green when the locate LED is on, `fail` is red when the fault LED is on
- the legend line goes to stderr, data lines to stdout
