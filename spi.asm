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
; Copyright (c) 2024 Aleksander Mazur
;
; Obsługa SPI / Three-Wire w trybie MASTER (tylko wysyłanie) pod kątem
; gadania z TM1628 (niestandardowo: najpierw najmłodszy bit),
; przy współdzielonych liniach DIO z SDA i CLK z SCL

spi_delay	macro
	nop
	nop
endm

;-----------------------------------------------------------
; START na SPI
spi_start:
	clr SPI_CLK	; żeby nie wywołać START na I2C
	setb SPI_DIO
	setb SPI_CLK
	clr SPI_STB
	ret

;-----------------------------------------------------------
; Wysyła bajt z akumulatora na SPI
; Na wejściu i na wyjściu STB=0, CLK=1
; Na wyjściu DIO=1
; Niszczy A, C, R7
spi_shout:
	mov	R7, #8
spi_shout_bit:
	rrc A	; od najmłodszego bitu do najstarszego
	clr SPI_CLK	; zmiana DIO przy ustawionym CLK mogłaby wywołać START albo STOP na I2C
	mov SPI_DIO, C
	spi_delay
	setb SPI_CLK
	spi_delay
	djnz R7, spi_shout_bit
	ret

spi_shout_stop:
	acall spi_shout
;-----------------------------------------------------------
; STOP na SPI
spi_stop:
	setb SPI_STB
	clr SPI_CLK	; żeby nie wywołać START na I2C
	setb SPI_DIO
	setb SPI_CLK
	ret
