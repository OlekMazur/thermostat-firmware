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
; Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2022 Aleksander Mazur
;
; Obsługa czujników na magistrali 1-wire
; Bazuje na niskopoziomowych procedurach z 1wire.asm i i2c.asm

;===========================================================
; Stałe

; komendy 1-wire
ds_search_rom		equ 0F0h
ds_skip_rom			equ 0CCh
ds_match_rom		equ 055h

;===========================================================
; Procedury

ifdef	TUNE_1WIRE
; Opóźnia działanie o ow_SEARCH_DELAY
; Na ten czas włącza silną jedynkę na magistrali 1-wire
; Niszczy C, R7
owhl_search_delay:
	load_delay ow_SEARCH_DELAY
	cjne R7, #0, owhl_search_delay_nz
	ret
owhl_search_delay_nz:
ifdef	OW_PARASITE
	clr OW_PWR
endif
	djnz R7, $
ifdef	OW_PARASITE
	setb OW_PWR
endif
	ret
endif

;-----------------------------------------------------------
; Znajduje pierwszy albo następny w kolejności czujnik na magistrali.
; Na wejściu magistrala powinna znajdować się w stanie tuż po resecie!
; Na wyjściu, znaleziony czujnik jest wybrany na magistrali (po SEARCH ROM)
; i można (a nawet trzeba) kontynuować komunikację z nim.
; Wejście:
; global_ow_diffpos - 0 przy enumeracji pierwszego czujnika,
;  albo pozycja bitu (1-64) z dwoma możliwościami przy kontynuacji.
; global_ow_id - tablica 8 bajtów z ID ostatnio znalezionego czujnika.
;  Zawartość nieistotna przy szukaniu pierwszego czujnika.
;  Przy szukaniu kolejnego czujnika musi tu pozostać ID czujnika
;  znalezionego ostatnio.
; Niszczy: A, B, C, R1, R2(CRC), R4, R5, R6, R7
; Zwraca:
;  C=0 jeśli sukces. ID znalezionego czujnika jest w global_ow_id.
;   Jeśli global_ow_diffpos <> 0, to ID do kupy z global_ow_diffpos
;   pozwala znaleźć następny czujnik przy kolejnym zawołaniu.
;   Wołający musi zapewnić nietykalność tym zmiennym do tego czasu.
;   Jeśli global_ow_diffpos = 0, to to już jest ostatni czujnik,
;   a kolejne zawołanie będzie szukać od początku.
;  C=1 jeśli błąd. W R4 (local_bit) jest zwracany kod błędu,
;   a konkretnie liczba bitów ID, które udało się poprawnie wczytać,
;   od 0 do 64. Wartość 64 oznacza, że wystąpił błąd CRC8.
local_ptr		equ R1	; wskaźnik do miejsca na aktualnie składany bajt w ID
local_bit		equ R4	; numer pozycji bieżącego bitu
local_nextpos	equ R5	; wartość global_ow_diffpos dla następnego wywołania
local_byte		equ R6	; składany bajt, który trafi do @local_ptr

owhl_enum_next:
	mov A, #ds_search_rom
	acall ow_write
	mov local_ptr, #global_ow_id
	clr A
	mov CRC, A
	mov local_bit, A
	mov local_nextpos, A
	;mov local_byte, A	; nie trzeba inicjować, bo i tak wpychamy tam wszystkie 8 bitów, zanim umieszczamy w @local_ptr
owhl_enum_next_bit:
	inc local_bit
	clr A
ifdef	TUNE_1WIRE
	acall owhl_search_delay
endif
	acall ow_read_bit			; czytamy bit niezanegowany
	rlc A
ifdef	TUNE_1WIRE
	acall owhl_search_delay
endif
	acall ow_read_bit			; czytamy bit zanegowany
	rlc A
	; tu C=0, bo z wyzerowanego akumulatora wyjeżdżają zera z lewej strony
ifdef	TUNE_1WIRE
	acall owhl_search_delay
	clr C	; przywracamy C=0, bo owhl_search_delay mogło je zniszczyć
endif
	; w A mamy jedną z 4 możliwości:
	; 00 - oba zera - trzeba będzie wybrać 0 albo 1
	; 01 - zero
	; 10 - jedynka
	; 11 - brak czujników o ID takim, jak znaleziony do tej pory (błąd)
	jz owhl_enum_select_bit		; oba zera - trzeba wybrać
	dec A
	; teraz w A:
	; 00 - zero
	; 01 - jedynka
	; 10 - brak czujników (błąd)
	; wciąż C=0
	rrc A
	jz owhl_enum_selected_bit	; bit jest w C
	; były dwie jedynki - błąd
	; cofamy licznik, bo nie udało się wczytać tego bitu
	dec local_bit
owhl_enum_next_error:
	mov A, local_byte
	mov @local_ptr, A
owhl_setC_ret:
	setb C
	ret
owhl_enum_select_bit:
	; procedura szukania dostała oba bity wyzerowane, czyli są na
	; magistrali czujniki mające na tej pozycji numeru seryjnego
	; zarówno 0, jak i 1, i musimy sobie wybrać, w którą gałąź teraz idziemy
	mov A, local_bit
	cjne A, global_ow_diffpos, owhl_enum_select_bit_not_at_diffpos
	; wybieramy 1, jeśli local_bit == global_ow_diffpos
owhl_enum_select_1:
	setb C
	sjmp owhl_enum_selected_bit
owhl_enum_select_bit_not_at_diffpos:
	; wybieramy 0, jeśli local_bit > global_ow_diffpos
	jnc owhl_enum_select_bit_zero
	; index < pos -> wybieramy taki sam bit, jak ostatnio na tej pozycji
	; local_ptr wskazuje na bajt zawierający m.in. bit bieżącej pozycji - musimy wydobyć z niego właściwy bit
	mov A, local_bit	; indeks bitu liczony od 1
	dec A
	anl A, #00000111b	; numer bitu liczony od 0 do 7 w ramach bieżącego bajtu
	mov B, A
	acall control_get_mask_1bit
	; w A mamy maskę na interesujący nas bit
	anl A, @local_ptr
	jnz owhl_enum_select_1
	clr C
owhl_enum_select_bit_zero:
	; zapamiętujemy ostatnie miejsce, gdzie wybraliśmy 0, żeby następnym razem wybrać tam 1
	mov A, local_bit
	mov local_nextpos, A
owhl_enum_selected_bit:
	; znaleźliśmy (lub wybraliśmy) kolejny bit numeru seryjnego jakiegoś czujnika
	; znaleziony bit jest w C
	acall ow_write_bit
	; wybrany bit jest częścią numeru właśnie wybieranego czujnika
	mov A, local_byte
	rrc A
	mov local_byte, A
	; czy mamy już cały bajt?
	mov A, local_bit
	anl A, #00000111b
	jnz owhl_enum_next_bit
	; mamy cały bajt
	mov A, local_byte
	mov @local_ptr, A
	inc local_ptr
	acall do_CRC8
	cjne local_bit, #64, owhl_enum_next_bit
	; znaleźliśmy cały numer seryjny jakiegoś czujnika
	; czujnik ten jest teraz wybrany na magistrali - można z nim gadać przez 1-wire
	; sprawdźmy CRC ROM-code
	mov A, CRC
	jnz owhl_enum_next_error	; błąd CRC; nie cofamy licznika, bo bit #64 udało się wczytać; dzięki temu stan licznika bitów określa jednoznacznie, czy był błąd CRC
	; sukces
	mov global_ow_diffpos, local_nextpos
	clr C
	ret

;-----------------------------------------------------------
; Wybiera czujnik o ID składającym się z:
; - family code z global_ow_id[0]
; - kolejnych 6 bajtach ID z EEPROM (i2c_shin, ACK, i2c_shin, ACK, i2c_shin, ACK, i2c_shin, ACK, i2c_shin, ACK, i2c_shin, i2c_NAK, i2c_stop)
; - CRC8 wyliczonym dla w/w danych
; Jeśli flag_overwrite_ow_id jest ustawiona, ID czujnika (7 bajtów poza pierwszym,
; który musi być zadany przed wywołaniem) jest dodatkowo umieszczane w global_ow_id.
; Niszczy A, B, C, R1, CRC, R6, R7.
; Zwraca C=0, jeśli sukces, a C=1, jeśli wystąpił błąd.
; W każdym przypadku funkcja kończy odczyt z EEPROM (eeprom_read_stop).
owhl_match_rom_from_eeprom:
	acall ow_reset
	jc eeprom_read_stop	; magistrala 1-wire nie funguje
	mov A, #ds_match_rom
	acall ow_write
	; wysyłamy family code i rozpoczynamy liczenie CRC
	mov R1, #global_ow_id
	mov A, @R1
	mov CRC, #0
	acall do_CRC8
	acall ow_write
	mov B, #6
	sjmp owhl_match_rom_from_eeprom_start
owhl_match_rom_from_eeprom_ack:
	acall i2c_ACK
owhl_match_rom_from_eeprom_start:
	; wysyłamy kolejne bajty z EEPROM i uaktualniamy CRC
	acall i2c_shin
ifdef	MATCH_ON_SEARCH_FAILURE
	acall owhl_match_rom_maybe_overwrite
endif	;MATCH_ON_SEARCH_FAILURE
	acall do_CRC8
	acall ow_write
	djnz B, owhl_match_rom_from_eeprom_ack
	acall eeprom_read_stop	; koniec odczytu z EEPROM
	; wysyłamy CRC
	mov A, CRC
ifdef	MATCH_ON_SEARCH_FAILURE
	acall owhl_match_rom_maybe_overwrite
endif	;MATCH_ON_SEARCH_FAILURE
	acall ow_write
	clr C
	ret

ifdef	MATCH_ON_SEARCH_FAILURE
owhl_match_rom_maybe_overwrite:
	jnb flag_overwrite_ow_id, owhl_dont_overwrite_ow_id
	inc R1
	mov @R1, A
owhl_dont_overwrite_ow_id:
	ret
endif	;MATCH_ON_SEARCH_FAILURE

;-----------------------------------------------------------
; Wybiera czujnik o ID składającym się z:
; - family code z global_ow_id[0]
; - kolejnych 6 bajtach ID z EEPROM (i2c_shin, ACK, i2c_shin, ACK, i2c_shin, ACK, i2c_shin, ACK, i2c_shin, ACK, i2c_shin, i2c_NAK, i2c_stop)
; - CRC8 wyliczonym dla w/w danych
; a następnie odczytuje jego scratchpad do local_scratchpad2.
; Jako, że family code bierzemy z pierwszego czujnika (global_ow_id),
; musi to być para tego samego modelu.
; Niszczy A, B, C, R1, CRC, R6, R7.
; Zwraca C=0, jeśli sukces, a C=1, jeśli wystąpił błąd.
; W każdym przypadku funkcja kończy odczyt z EEPROM (eeprom_read_stop).
owhl_read_second_scratchpad:
ifdef	MATCH_ON_SEARCH_FAILURE
	clr flag_overwrite_ow_id
endif	;MATCH_ON_SEARCH_FAILURE
	acall owhl_match_rom_from_eeprom
	jc owhl_read_second_scratchpad_ret
	; w tym miejscu powinniśmy mieć wybrany czujnik na magistrali 1-wire
	mov R1, #local_scratchpad2
	acall owhl_read_scratchpad
	; konwersja statusu z A na C
	jnz owhl_setC_ret
	clr C
owhl_read_second_scratchpad_ret:
	ret
