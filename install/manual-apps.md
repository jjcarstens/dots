# Manual app installs

Apps with no reliable cask / scriptable download. All self-update once installed,
so this is a one-time step per machine.

## Base set (always install)

| App      | Where               | Notes                                            |
| -------- | ------------------- | ------------------------------------------------ |
| Tidewave | https://tidewave.ai | No stable direct-download URL; get the macOS app from the site. |

> reMarkable is a Mac App Store app — see `mas.txt` (id 1276493162).

## Optional / situational (install only when needed on a given machine)

Vendor / hardware tools — not part of the base set:

- CP210xVCPDriver — Silicon Labs USB-UART driver (silabs.com)
- SEGGER J-Link — segger.com/downloads
- qFlipper — Flipper Zero tooling (flipperzero.one)
- Raspberry Pi Imager — raspberrypi.com/software
- Display Pilot 2 — BenQ monitor software; install only on machines that will
  connect that monitor.
