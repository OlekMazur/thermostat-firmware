# Thermostat firmware
#
# Copyright (c) 2022 Aleksander Mazur

VARIANTS=$(wildcard firmware_*.asm)
HEX_FILES=$(patsubst %.asm,%.hex,$(VARIANTS))
BIN_FILES=$(patsubst %.asm,%.bin,$(VARIANTS))
LST_FILES=$(patsubst %.asm,%.lst,$(VARIANTS))
ASM_FILES=$(wildcard *.asm)
SRC_FILES=$(filter-out $(VARIANTS),$(ASM_FILES))

.PHONY:	all clean

all:	$(BIN_FILES) $(HEX_FILES)
	./api.sh

clean:
	rm $(BIN_FILES) $(HEX_FILES) font.asm

%.hex:	%.asm $(SRC_FILES) font.asm
	asem -i /usr/local/share/asem-51/1.3/mcu $<

%.bin:	%.hex
	hexbin $< $@

font.asm:	font.py
	./$< > $@
