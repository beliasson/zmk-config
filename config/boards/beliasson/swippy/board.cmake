# SPDX-License-Identifier: MIT

board_runner_args(nrfjprog "--nrf-family=NRF52" "--softreset")
set(OPENOCD_NRF5_SUBFAMILY "nrf52")
set(OPENOCD_NRF5_INTERFACE "stlink")
include(${ZEPHYR_BASE}/boards/common/openocd-nrf5.board.cmake)
include(${ZEPHYR_BASE}/boards/common/uf2.board.cmake)
include(${ZEPHYR_BASE}/boards/common/nrfjprog.board.cmake)
