; This file is part of Thermostat Firmware.
;
; Thermostat Firmware is free software: you can redistribute it and/or
; modify it under the terms of the GNU General Public License as
; published by the Free Software Foundation, either version 3 of the
; License, or (at your option) any later version.
;
; Thermostat Firmware is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
; General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with Thermostat Firmware. If not, see <https://www.gnu.org/licenses/>.
;
; Copyright (c) 2013, 2018 Aleksander Mazur
;
; Obliczanie CRC-8 zgodnie z 1-wire

;-----------------------------------------------------------
; uaktualnia CRC8 w zmiennej CRC bajtem z akumulatora
; niszczy C, R7
; używa stosu
; zajmuje 19 bajtów, jeśli CRC jest rejestrem Rx
; w innym wypadku 22 bajty
do_CRC8:
	; mamy 8 bitów do przeliczenia
	mov R7, #8
do_CRC8_loop:
	push ACC
	; C = (x ^ CRC) & 1;
	xrl A, CRC
	rrc A
	; CRC = (C << 7) | ((C ? CRC ^ 0x18 : CRC) >> 1);
	mov A, CRC
	jnc do_CRC8_zero
	xrl A, #18h
do_CRC8_zero:
	rrc A
	mov CRC, A
	; x >>= 1;
	pop ACC
	rr A
	djnz R7, do_CRC8_loop
	ret
