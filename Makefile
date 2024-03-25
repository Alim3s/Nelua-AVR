#### Based Auto generated microchip studio makefile ####

#### dectect OS ####
ifeq ($(OS),Windows_NT)
    SYS := Windows
else
    ifeq ($(UNAME_S),Linux)
		SYS := Linux
    endif
    ifeq ($(UNAME_S),Darwin)
        SYS := macOS
    endif
endif

#### Arguments ####
Source?=./main.nelua

Build_Dir?=./build

TARGET?=atmega128a #currently only atmega is supported
####################

nelua:=$(abspath ./NeluaLang/nelua.bat)


QTE:="#QTE

TOOLS:=./avr8_GNU_toolchain/bin
CC:=$(QTE)$(abspath $(TOOLS)/avr-gcc.exe)$(QTE)
OBJCOPY:=$(QTE)$(abspath $(TOOLS)/avr-objcopy.exe)$(QTE)
OBJDUMP:=$(QTE)$(abspath $(TOOLS)/avr-objdump.exe)$(QTE)
AVRSIZE:=$(QTE)$(abspath $(TOOLS)/avr-size.exe)$(QTE)

Nelua_COMPILE:=.nelua
C_COMPILE:=.c

#### Dectect SourceFile extension ####
SourceFileExtension := $(suffix $(Source))
dectectExtension:
	@echo Dectecting extension...
	@echo SourceFile extension is $(QTE)$(SourceFileExtension)$(QTE)
	@echo ---------------------------------------


#Source_extension ?= nelua # nelua or C

#Currently, only Windows is supported sorry!



#Make new directory(folder)
newDirectory: 
	@echo ---------------------------------------
	@echo Making build directory...
ifeq ($(SYS), Windows)
	--mkdir $(QTE)$(Build_Dir)$(QTE)
else
	$(shell mkdir -p $(Build_Dir))
endif
	@echo Done!
	@echo ---------------------------------------




CFLAGS:=-x c -funsigned-char -funsigned-bitfields -DDEBUG  -Og -ffunction-sections -fdata-sections -fpack-struct -fshort-enums -mrelax -g2 -Wall -mmcu=$(TARGET) -c -std=gnu99

SourceFileName:=$(basename $(notdir $(Source)))

Code_Path:=$(abspath $(Build_Dir)/$(SourceFileName))
#Obj_Path:=$(Build_Dir)/$(SourceFileName)


$(Nelua_COMPILE):
	@echo Converting Nelua code to C code...
	$(nelua) -o $(Code_Path).c --add-path="./NeluaAVRLib" --cc $(CC) $(Source)
	@echo Done!
	@echo ---------------------------------------
	@echo Compiling C code...
	$(CC) $(CFLAGS) -MD -MP -MF "$(Code_Path).d" -MT"$(Code_Path).d" -MT"$(Code_Path).o" -o "$(Code_Path).o" "$(Code_Path).c" 
	@echo Done!
	@echo ---------------------------------------


$(C_COMPILE):
	@echo Compiling C code...
	$(CC) $(CFLAGS) -MD -MP -MF "$(Code_Path).d" -MT"$(Code_Path).d" -MT"$(Code_Path).o" -o "$(Code_Path).o" "$(Source).c" 
	@echo

linking:
	@echo Linking code...
	$(CC) -o $(Code_Path).elf $(Code_Path).o -Wl,-Map=$(QTE)$(abspath $(Code_Path)).map$(QTE) -Wl,--start-group -Wl,-lm  -Wl,--end-group -Wl,--gc-sections -mrelax -mmcu=$(TARGET) -B $(TARGETPACK)

	$(OBJCOPY) -O ihex -R .eeprom -R .fuse -R .lock -R .signature -R .user_signatures  $(QTE)$(Code_Path).elf$(QTE) $(QTE)$(Code_Path).hex$(QTE)
	$(OBJCOPY) -j .eeprom  --set-section-flags=.eeprom=alloc,load --change-section-lma .eeprom=0  --no-change-warnings -O ihex $(QTE)$(Code_Path).elf$(QTE) $(QTE)$(Code_Path).eep$(QTE) || exit 0
	$(OBJDUMP) -h -S $(QTE)$(Code_Path).elf$(QTE) > $(QTE)$(Code_Path).lss$(QTE)
	$(OBJCOPY) -O srec -R .eeprom -R .fuse -R .lock -R .signature -R .user_signatures $(QTE)$(Code_Path).elf$(QTE) $(QTE)$(Code_Path).srec$(QTE)
	$(AVRSIZE) $(QTE)$(Code_Path).elf$(QTE)
	@echo Done!
	@echo ---------------------------------------
	@echo Build finished!

build : newDirectory dectectExtension $(SourceFileExtension) linking
