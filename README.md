# Nelua-AVR
Work In Process

Currently, this code only supports Windows and ATmega

How to use :

  `make build Source=YOUR_SRC_PATH Build_Dir=YOUR_BUILD_DIRECTORY TARGET=atmegaXXX`
  
  Arguments :   
    Source : Path to your C or Nelua source code  
    EX) Source=./main.nelua  
      
    Build_Dir : Path to Your Build Directory(folder)  
    it will be made automatically  
    EX) Build_Dir=./build  
      
    TARGET : Select microcontroller  
    EX) TARGET=atmega128A  
