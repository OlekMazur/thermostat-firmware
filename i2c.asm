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
; Copyright (c) 2006, 2018, 2022 Aleksander Mazur
;
; Obsługa I2C / Two-Wire w trybie MASTER
;
; na podstawie "Interfacing AT24CXX Serial EEPROMs with AT89CX051 MCU" firmy Atmel

;-----------------------------------------------------------
; START na I2C
; zwraca C=1 jeśli wystąpił błąd
; niszczy A, C
i2c_start:
	setb SCL
	setb SDA
	jnb SCL, i2c_error
	jb SDA, i2c_start_cont
	;push ACC
	mov A, #9
i2c_reset_loop:
	clr SCL
	i2c_delay
	setb SCL
	i2c_delay
	jb SDA, i2c_start_cont_pop
	djnz ACC, i2c_reset_loop
	;pop ACC
i2c_error:
	setb C
	ret
i2c_start_cont_pop:
	;pop ACC
i2c_start_cont:
	clr C
	i2c_delay
	clr SDA
	i2c_delay
i2c_clr_SCL_ret:
	clr SCL
	ret

;-----------------------------------------------------------
; Wysyła bajt z akumulatora na I2C
; Niszczy A, C, R7
; Zwraca C=1 w razie błędu, C=0 po sukcesie
i2c_shout:
	mov	R7, #8
i2c_shout_bit:
	rlc A
	mov SDA, C
	i2c_delay
	setb SCL
	i2c_delay
	clr SCL
	djnz R7, i2c_shout_bit
	setb SDA
	i2c_delay
	setb SCL
	i2c_delay
	mov C, SDA
	sjmp i2c_clr_SCL_ret

;-----------------------------------------------------------
; ACK na I2C
i2c_ACK:
	clr SDA
	i2c_delay
	setb SCL
	i2c_delay
	sjmp i2c_clr_SCL_ret

;-----------------------------------------------------------
; NAK na I2C
i2c_NAK:
	setb SDA
	i2c_delay
	setb SCL
	i2c_delay
	sjmp i2c_clr_SCL_ret

;-----------------------------------------------------------
; STOP na I2C
i2c_stop:
	clr	SDA
	i2c_delay
	setb SCL
	i2c_delay
	setb SDA
	ret
