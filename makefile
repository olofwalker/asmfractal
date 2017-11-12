
all: 
	nasm -f elf64 main.s -o main.o
	ld main.o -o main

