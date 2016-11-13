	IMAGE_WIDTH 	equ 640	
	IMAGE_HEIGHT 	equ 480
	IMAGE_DEPTH		equ	3
	IMAGE_SIZE		equ IMAGE_WIDTH * IMAGE_HEIGHT * IMAGE_DEPTH
	MAX_ITER		equ	1023
	
	;; ------------- sysCall
	%macro sysCall	4
    mov     eax,%1
    mov     ebx,%2                              ;file descriptor (stdout)
    mov     ecx,%3
    mov     edx,%4
    int     0x80                                ;call kernel
	%endmacro

	;; -------------  print
	%macro print 2
	sysCall 0x4,0x1,%1,%2
	%endmacro

	;; ------------- openFile
	;; %1 = FD
	;; %2 = Name
	;; %3 = Length of name
	%macro openFile	3
	sysCall 0x5,%1,%2,%3
	%endmacro

	;; ------------- createFD
	;; %1 = filename
	%macro createFD 1
	sysCall 0x8,%1,0777q,0 
	%endmacro

	;; ------------- writeFile
	;; %1 = FD
	;; %2 = Data
	;; %3 = Length of data
	%macro writeFile	3
	sysCall 0x4,%1,%2,%3
	%endmacro

	;; ------------- closeFile
	;; %1 = FD
	%macro closeFile	1
	sysCall 0x6,%1,0,0
	%endmacro
	
section     .text
global      _start                              ;must be declared for linker (ld)
_start:                                         ;tell linker entry point
	call 	init
	print 	msg,len

	call renderFractal

	;; Create file
	createFD	fileName
	mov r8,rax
	writeFile r8d,arrayPtr, IMAGE_SIZE
	closeFile r8d

	;; quit
    mov     eax,1
    int     0x80 
	
renderFractal:
	;; R9	X
	;; R10	Y
	;; R11 	Zoom
	;; R12	moveX
	;; R13	moveY
	xor r9d,r9d
	xor r10d,r10d

loopY:	
	;;  pr = 1.5 * (x - w / 2) / (0.5 * zoom * w) + moveX;
	pxor xmm0,xmm0 
	pxor xmm1,xmm1
	pxor xmm2,xmm2
	;; (0.5 * zoom * w)
	cvtsi2sd xmm0, [width]		; convert integer to double
	cvtsi2sd xmm1,[zoom]		; convert integer to double
	mulsd xmm0,xmm1				; w*zoom
	mulsd xmm0,[half]			; w*zom * 0.5
	;; (x - w /2)
	cvtsi2sd xmm1, [width]		; w / 2
	divsd xmm1, [two]			; 
	cvtsi2sd xmm2, r9			; x
	subsd xmm2,xmm1				; x - w/2
	;; 1.5
	mulsd xmm2,[oneHalf]		;
	;; /
	divsd xmm2,xmm0				;
	;; +
	addsd xmm2,[moveX]			;
	movsd [pr],xmm2
	
	;;  pi = (y - h / 2) / (0.5 * zoom * h) + moveY;
	pxor xmm0,xmm0 
	pxor xmm1,xmm1
	pxor xmm2,xmm2
	;; (0.5 * zoom * h)
	cvtsi2sd xmm0, [height]		; convert integer to double
	cvtsi2sd xmm1,[zoom]		; convert integer to double
	mulsd xmm0,xmm1				; h*zoom
	mulsd xmm0,[half]			; h*zom * 0.5
	;; (x - h /2)
	cvtsi2sd xmm1, [height]		; h / 2
	divsd xmm1, [two]			; 
	cvtsi2sd xmm2, r10			; y
	subsd xmm2,xmm1				; y - h/2
	;; /
	divsd xmm2,xmm0				;
	;; +
	addsd xmm2,[moveY]			;
	movsd [pi],xmm2
	
	mov qword [newIm], 0
	mov qword [newRe], 0 
	mov qword [oldIm], 0
	mov qword [oldRe], 0	

	xor rax,rax
	movsd xmm2,[four]
iter:

	movsd xmm0,[newRe]
	movsd qword [oldRe],xmm0

	movsd xmm0,[newIm]
	movsd qword [oldIm],xmm0
	
	;; newRe = oldRe * oldRe - oldIm * oldIm + pr;
	movsd xmm0,[oldRe]
	mulsd xmm0,[oldRe]

	movsd xmm1,[oldIm]
	mulsd xmm1,[oldIm]

	subsd xmm0,xmm1
	addsd xmm0,[pr]
	movsd [newRe],xmm0
	
	;; newIm = 2 * oldRe * oldIm + pi;
	movsd xmm0,[two]
	mulsd xmm0,[oldRe]
	mulsd xmm0,[oldIm]
	addsd xmm0,[pi]
	movsd [newIm],xmm0

	;; if((newRe * newRe + newIm * newIm) > 4) break
	movsd xmm0,[newRe]
	mulsd xmm0,[newRe]
	movsd xmm1,[newIm]
	mulsd xmm1,[newIm]
	addsd xmm0,xmm1

	comisd xmm0,xmm2
	ja iterDone
	
	;; loop
	add ax,1
	cmp ax,MAX_ITER
	jne iter
	
iterDone:	

	;; double z = sqrt(newRe * newRe + newIm * newIm);
	;; sqrtss xmm1,xmm0
	;; int brightness = 256. * log2(1.75 + i - log2(log2(z))) / log2(double(maxIterations));

	;; i % 256
	xor r14,r14
	test ax,MAX_ITER
	je escapeBlack
	
stop:

	;; base address
	mov ecx,palette

	sub eax,1	
	xor rdx,rdx
	mov rsi,1024				; number of colors
	div rsi						; div iteration, number of colors
	shl rdx,2					; mul 4 to get the address

	;; base address of palette i ecx
	add rcx,rdx
	;// RGB
	mov r14b,[ecx]
	add ecx,1
	shl r14,8
	mov r14b,[ecx]
	add ecx,1
	shl r14,8
	mov r14b,[ecx]
	
escapeBlack:	
	call setPixel
		
	add r9d,1
	cmp r9d,IMAGE_WIDTH
	jne loopY
	xor r9d,r9d	
	
	add r10d,1
	cmp	r10d,IMAGE_HEIGHT
	jne loopY
	
	ret

setPixel:
	;; R9 	X
	;; R10 	Y
	;; R14 	color
	
	mov eax,r10d 				; Load Y
	mov r15d, IMAGE_WIDTH		; Load Image Width
	mul r15d
	mov r15d, IMAGE_DEPTH		; Load Image depth (bytes per pixel)
	mul r15d					; Y * width * depth
	mov r8d,eax
	mov eax,r9d					;
	mul r15d					; X * width
	add eax,r8d					; (X * DEPTH) + (Y * WIDTH * DEPTH)
	
	mov [arrayPtr + eax+2],r14b
	shr r14,8
	mov [arrayPtr + eax+1],r14b
	shr r14,8
	mov [arrayPtr + eax],r14b
	ret

init:
	mov qword [pi], 0
	mov qword [pr], 0
	mov qword [oldRe], 0
	mov qword [oldIm], 0
	mov qword [newRe], 0
	mov qword [newIm], 0
	ret

section     .data
	two		dq 2.0
	four	dq 4.0
	width	dq IMAGE_WIDTH
	height	dq IMAGE_HEIGHT
	moveX	dq 0
	moveY	dq 0
	zoom	dq 1
	
	msg 	db  'Generating fractal !',0xa
	len 	equ $ - msg                   

	fileName	db 'fractal.data',0x0
	fileNameLen equ $ - fileName

	oneHalf	dq 1.5
	half	dq 0.5

palette:
db 0, 0, 255, 0
db 1, 1, 255, 0
db 1, 1, 255, 0
db 1, 1, 255, 0
db 1, 1, 255, 0
db 1, 2, 255, 0
db 2, 2, 255, 0
db 2, 2, 255, 0	
db 2, 2, 255, 0
db 2, 2, 255, 0
db 2, 3, 255, 0
db 3, 3, 255, 0
db 3, 3, 255, 0
db 3, 3, 255, 0
db 3, 3, 255, 0
db 3, 4, 255, 0
db 4, 4, 255, 0
db 4, 4, 255, 0
db 4, 4, 255, 0
db 4, 5, 255, 0
db 4, 5, 255, 0
db 5, 5, 255, 0
db 5, 5, 255, 0
db 5, 5, 255, 0
db 5, 6, 255, 0
db 5, 6, 255, 0
db 6, 6, 255, 0
db 6, 6, 255, 0
db 6, 6, 255, 0
db 6, 7, 255, 0
db 6, 7, 255, 0
db 7, 7, 255, 0
db 7, 7, 255, 0
db 7, 8, 255, 0
db 7, 8, 255, 0
db 7, 8, 255, 0
db 8, 8, 255, 0
db 8, 8, 255, 0
db 8, 9, 255, 0
db 8, 9, 255, 0
db 8, 9, 255, 0
db 9, 9, 255, 0
db 9, 9, 255, 0
db 9, 10, 255, 0
db 9, 10, 255, 0
db 9, 10, 255, 0
db 10, 10, 255, 0
db 10, 11, 255, 0
db 10, 11, 255, 0
db 10, 11, 255, 0
db 10, 11, 255, 0
db 11, 11, 255, 0
db 11, 12, 255, 0
db 11, 12, 255, 0
db 11, 12, 255, 0
db 11, 12, 255, 0
db 12, 12, 255, 0
db 12, 13, 255, 0
db 12, 13, 255, 0
db 12, 13, 255, 0
db 12, 13, 255, 0
db 13, 13, 255, 0
db 13, 14, 255, 0
db 13, 14, 255, 0
db 13, 14, 255, 0
db 13, 14, 255, 0
db 14, 15, 255, 0
db 14, 15, 255, 0
db 14, 15, 255, 0
db 14, 15, 255, 0
db 14, 15, 255, 0
db 15, 16, 255, 0
db 15, 16, 255, 0
db 15, 16, 255, 0
db 15, 16, 255, 0
db 15, 16, 255, 0
db 16, 17, 255, 0
db 16, 17, 255, 0
db 16, 17, 255, 0
db 16, 17, 255, 0
db 16, 18, 255, 0
db 17, 18, 255, 0
db 17, 18, 255, 0
db 17, 18, 255, 0
db 17, 18, 255, 0
db 17, 19, 255, 0
db 18, 19, 255, 0
db 18, 19, 255, 0
db 18, 19, 255, 0
db 18, 19, 255, 0
db 18, 20, 255, 0
db 19, 20, 255, 0
db 19, 20, 255, 0
db 19, 20, 255, 0
db 19, 21, 255, 0
db 19, 21, 255, 0
db 20, 21, 255, 0
db 20, 21, 255, 0
db 20, 21, 255, 0
db 20, 22, 255, 0
db 20, 22, 255, 0
db 21, 22, 255, 0
db 21, 22, 255, 0
db 21, 22, 255, 0
db 21, 23, 255, 0
db 21, 23, 255, 0
db 22, 23, 255, 0
db 22, 23, 255, 0
db 22, 23, 255, 0
db 22, 24, 255, 0
db 22, 24, 255, 0
db 23, 24, 255, 0
db 23, 24, 255, 0
db 23, 25, 255, 0
db 23, 25, 255, 0
db 23, 25, 255, 0
db 24, 25, 255, 0
db 24, 25, 255, 0
db 24, 26, 255, 0
db 24, 26, 255, 0
db 24, 26, 255, 0
db 25, 26, 255, 0
db 25, 26, 255, 0
db 25, 27, 255, 0
db 25, 27, 255, 0
db 25, 27, 255, 0
db 26, 27, 255, 0
db 26, 28, 255, 0
db 26, 28, 255, 0
db 26, 28, 255, 0
db 26, 28, 255, 0
db 27, 28, 255, 0
db 27, 29, 255, 0
db 27, 29, 255, 0
db 27, 29, 255, 0
db 27, 29, 255, 0
db 28, 29, 255, 0
db 28, 30, 255, 0
db 28, 30, 255, 0
db 28, 30, 255, 0
db 28, 30, 255, 0
db 29, 31, 255, 0
db 29, 31, 255, 0
db 29, 31, 255, 0
db 29, 31, 255, 0
db 29, 31, 255, 0
db 30, 32, 255, 0
db 30, 32, 255, 0
db 30, 32, 255, 0
db 30, 32, 255, 0
db 30, 32, 255, 0
db 31, 33, 255, 0
db 31, 33, 255, 0
db 31, 33, 255, 0
db 31, 33, 255, 0
db 31, 33, 255, 0
db 32, 34, 255, 0
db 32, 34, 255, 0
db 32, 34, 255, 0
db 32, 34, 255, 0
db 32, 35, 255, 0
db 33, 35, 255, 0
db 33, 35, 255, 0
db 33, 35, 255, 0
db 33, 35, 255, 0
db 33, 36, 255, 0
db 34, 36, 255, 0
db 34, 36, 255, 0
db 34, 36, 255, 0
db 34, 36, 255, 0
db 34, 37, 255, 0
db 35, 37, 255, 0
db 35, 37, 255, 0
db 35, 37, 255, 0
db 35, 38, 255, 0
db 35, 38, 255, 0
db 36, 38, 255, 0
db 36, 38, 255, 0
db 36, 38, 255, 0
db 36, 39, 255, 0
db 36, 39, 255, 0
db 37, 39, 255, 0
db 37, 39, 255, 0
db 37, 39, 255, 0
db 37, 40, 255, 0
db 37, 40, 255, 0
db 38, 40, 255, 0
db 38, 40, 255, 0
db 38, 41, 255, 0
db 38, 41, 255, 0
db 38, 41, 255, 0
db 39, 41, 255, 0
db 39, 41, 255, 0
db 39, 42, 255, 0
db 39, 42, 255, 0
db 39, 42, 255, 0
db 40, 42, 255, 0
db 40, 42, 255, 0
db 40, 43, 255, 0
db 40, 43, 255, 0
db 40, 43, 255, 0
db 41, 43, 255, 0
db 41, 44, 255, 0
db 41, 44, 255, 0
db 41, 44, 255, 0
db 41, 44, 255, 0
db 42, 44, 255, 0
db 42, 45, 255, 0
db 42, 45, 255, 0
db 42, 45, 255, 0
db 42, 45, 255, 0
db 43, 45, 255, 0
db 43, 46, 255, 0
db 43, 46, 255, 0
db 43, 46, 255, 0
db 43, 46, 255, 0
db 44, 46, 255, 0
db 44, 47, 255, 0
db 44, 47, 255, 0
db 44, 47, 255, 0
db 44, 47, 255, 0
db 45, 48, 255, 0
db 45, 48, 255, 0
db 45, 48, 255, 0
db 45, 48, 255, 0
db 45, 48, 255, 0
db 46, 49, 255, 0
db 46, 49, 255, 0
db 46, 49, 255, 0
db 46, 49, 255, 0
db 46, 49, 255, 0
db 47, 50, 255, 0
db 47, 50, 255, 0
db 47, 50, 255, 0
db 47, 50, 255, 0
db 47, 51, 255, 0
db 48, 51, 255, 0
db 48, 51, 255, 0
db 48, 51, 255, 0
db 48, 51, 255, 0
db 48, 52, 255, 0
db 49, 52, 255, 0
db 49, 52, 255, 0
db 49, 52, 255, 0
db 49, 52, 255, 0
db 49, 53, 255, 0
db 50, 53, 255, 0
db 50, 53, 255, 0
db 50, 53, 255, 0
db 50, 54, 255, 0
db 50, 54, 255, 0
db 51, 54, 255, 0
db 51, 54, 255, 0
db 51, 54, 255, 0
db 51, 55, 255, 0
db 51, 55, 255, 0
db 51, 55, 255, 0
db 52, 55, 255, 0
db 52, 55, 255, 0
db 52, 56, 255, 0
db 52, 56, 255, 0
db 52, 56, 255, 0
db 53, 56, 255, 0
db 53, 56, 255, 0
db 53, 57, 255, 0
db 53, 57, 255, 0
db 53, 57, 255, 0
db 54, 57, 255, 0
db 54, 58, 255, 0
db 54, 58, 255, 0
db 54, 58, 255, 0
db 54, 58, 255, 0
db 55, 58, 255, 0
db 55, 59, 255, 0
db 55, 59, 255, 0
db 55, 59, 255, 0
db 55, 59, 255, 0
db 56, 59, 255, 0
db 56, 60, 255, 0
db 56, 60, 255, 0
db 56, 60, 255, 0
db 56, 60, 255, 0
db 57, 61, 255, 0
db 57, 61, 255, 0
db 57, 61, 255, 0
db 57, 61, 255, 0
db 57, 61, 255, 0
db 58, 62, 255, 0
db 58, 62, 255, 0
db 58, 62, 255, 0
db 58, 62, 255, 0
db 58, 62, 255, 0
db 59, 63, 255, 0
db 59, 63, 255, 0
db 59, 63, 255, 0
db 59, 63, 255, 0
db 59, 64, 255, 0
db 60, 64, 255, 0
db 60, 64, 255, 0
db 60, 64, 255, 0
db 60, 64, 255, 0
db 60, 65, 255, 0
db 61, 65, 255, 0
db 61, 65, 255, 0
db 61, 65, 255, 0
db 61, 65, 255, 0
db 61, 66, 255, 0
db 62, 66, 255, 0
db 62, 66, 255, 0
db 62, 66, 255, 0
db 62, 66, 255, 0
db 62, 67, 255, 0
db 63, 67, 255, 0
db 63, 67, 255, 0
db 63, 67, 255, 0
db 63, 68, 255, 0
db 63, 68, 255, 0
db 64, 68, 255, 0
db 64, 68, 255, 0
db 64, 68, 255, 0
db 64, 69, 255, 0
db 64, 69, 255, 0
db 65, 69, 255, 0
db 65, 69, 255, 0
db 65, 69, 255, 0
db 65, 70, 255, 0
db 65, 70, 255, 0
db 66, 70, 255, 0
db 66, 70, 255, 0
db 66, 71, 255, 0
db 66, 71, 255, 0
db 66, 71, 255, 0
db 67, 71, 255, 0
db 67, 71, 255, 0
db 67, 72, 255, 0
db 67, 72, 255, 0
db 67, 72, 255, 0
db 68, 72, 255, 0
db 68, 72, 255, 0
db 68, 73, 255, 0
db 68, 73, 255, 0
db 68, 73, 255, 0
db 69, 73, 255, 0
db 69, 74, 255, 0
db 69, 74, 255, 0
db 69, 74, 255, 0
db 69, 74, 255, 0
db 70, 74, 255, 0
db 70, 75, 255, 0
db 70, 75, 255, 0
db 70, 75, 255, 0
db 70, 75, 255, 0
db 71, 75, 255, 0
db 71, 76, 255, 0
db 71, 76, 255, 0
db 71, 76, 255, 0
db 71, 76, 255, 0
db 72, 77, 255, 0
db 72, 77, 255, 0
db 72, 77, 255, 0
db 72, 77, 255, 0
db 72, 77, 255, 0
db 73, 78, 255, 0
db 73, 78, 255, 0
db 73, 78, 255, 0
db 73, 78, 255, 0
db 73, 78, 255, 0
db 74, 79, 255, 0
db 74, 79, 255, 0
db 74, 79, 255, 0
db 74, 79, 255, 0
db 74, 79, 255, 0
db 75, 80, 255, 0
db 75, 80, 255, 0
db 75, 80, 255, 0
db 75, 80, 255, 0
db 75, 81, 255, 0
db 76, 81, 255, 0
db 76, 81, 255, 0
db 76, 81, 255, 0
db 76, 81, 255, 0
db 76, 82, 255, 0
db 77, 82, 255, 0
db 77, 82, 255, 0
db 77, 82, 255, 0
db 77, 82, 255, 0
db 77, 83, 255, 0
db 78, 83, 255, 0
db 78, 83, 255, 0
db 78, 83, 255, 0
db 78, 84, 255, 0
db 78, 84, 255, 0
db 79, 84, 255, 0
db 79, 84, 255, 0
db 79, 84, 255, 0
db 79, 85, 255, 0
db 79, 85, 255, 0
db 80, 85, 255, 0
db 80, 85, 255, 0
db 80, 85, 255, 0
db 80, 86, 255, 0
db 80, 86, 255, 0
db 81, 86, 255, 0
db 81, 86, 255, 0
db 81, 87, 255, 0
db 81, 87, 255, 0
db 81, 87, 255, 0
db 82, 87, 255, 0
db 82, 87, 255, 0
db 82, 88, 255, 0
db 82, 88, 255, 0
db 82, 88, 255, 0
db 83, 88, 255, 0
db 83, 88, 255, 0
db 83, 89, 255, 0
db 83, 89, 255, 0
db 83, 89, 255, 0
db 84, 89, 255, 0
db 84, 89, 255, 0
db 84, 90, 255, 0
db 84, 90, 255, 0
db 84, 90, 255, 0
db 85, 90, 255, 0
db 85, 91, 255, 0
db 85, 91, 255, 0
db 85, 91, 255, 0
db 85, 91, 255, 0
db 86, 91, 255, 0
db 86, 92, 255, 0
db 86, 92, 255, 0
db 86, 92, 255, 0
db 86, 92, 255, 0
db 87, 92, 255, 0
db 87, 93, 255, 0
db 87, 93, 255, 0
db 87, 93, 255, 0
db 87, 93, 255, 0
db 88, 94, 255, 0
db 88, 94, 255, 0
db 88, 94, 255, 0
db 88, 94, 255, 0
db 88, 94, 255, 0
db 89, 95, 255, 0
db 89, 95, 255, 0
db 89, 95, 255, 0
db 89, 95, 255, 0
db 89, 95, 255, 0
db 90, 96, 255, 0
db 90, 96, 255, 0
db 90, 96, 255, 0
db 90, 96, 255, 0
db 90, 97, 255, 0
db 91, 97, 255, 0
db 91, 97, 255, 0
db 91, 97, 255, 0
db 91, 97, 255, 0
db 91, 98, 255, 0
db 92, 98, 255, 0
db 92, 98, 255, 0
db 92, 98, 255, 0
db 92, 98, 255, 0
db 92, 99, 255, 0
db 93, 99, 255, 0
db 93, 99, 255, 0
db 93, 99, 255, 0
db 93, 99, 255, 0
db 93, 100, 255, 0
db 94, 100, 255, 0
db 94, 100, 255, 0
db 94, 100, 255, 0
db 94, 101, 255, 0
db 94, 101, 255, 0
db 95, 101, 255, 0
db 95, 101, 255, 0
db 95, 101, 255, 0
db 95, 102, 255, 0
db 95, 102, 255, 0
db 96, 102, 255, 0
db 96, 102, 255, 0
db 96, 102, 255, 0
db 96, 103, 255, 0
db 96, 103, 255, 0
db 97, 103, 255, 0
db 97, 103, 255, 0
db 97, 104, 255, 0
db 97, 104, 255, 0
db 97, 104, 255, 0
db 98, 104, 255, 0
db 98, 104, 255, 0
db 98, 105, 255, 0
db 98, 105, 255, 0
db 98, 105, 255, 0
db 99, 105, 255, 0
db 99, 105, 255, 0
db 99, 106, 255, 0
db 99, 106, 255, 0
db 99, 106, 255, 0
db 100, 106, 255, 0
db 100, 107, 255, 0
db 100, 107, 255, 0
db 100, 107, 255, 0
db 100, 107, 255, 0
db 101, 107, 255, 0
db 101, 108, 255, 0
db 101, 108, 255, 0
db 101, 108, 255, 0
db 101, 108, 255, 0
db 102, 108, 255, 0
db 102, 109, 255, 0
db 102, 109, 255, 0
db 102, 109, 255, 0
db 102, 109, 255, 0
db 102, 109, 255, 0
db 103, 110, 255, 0
db 103, 110, 255, 0
db 103, 110, 255, 0
db 103, 110, 255, 0
db 103, 111, 255, 0
db 104, 111, 255, 0
db 104, 111, 255, 0
db 104, 111, 255, 0
db 104, 111, 255, 0
db 104, 112, 255, 0
db 105, 112, 255, 0
db 105, 112, 255, 0
db 105, 112, 255, 0
db 105, 112, 255, 0
db 105, 113, 255, 0
db 106, 113, 255, 0
db 106, 113, 255, 0
db 106, 113, 255, 0
db 106, 114, 255, 0
db 106, 114, 255, 0
db 107, 114, 255, 0
db 107, 114, 255, 0
db 107, 114, 255, 0
db 107, 115, 255, 0
db 107, 115, 255, 0
db 108, 115, 255, 0
db 108, 115, 255, 0
db 108, 115, 255, 0
db 108, 116, 255, 0
db 108, 116, 255, 0
db 109, 116, 255, 0
db 109, 116, 255, 0
db 109, 117, 255, 0
db 109, 117, 255, 0
db 109, 117, 255, 0
db 110, 117, 255, 0
db 110, 117, 255, 0
db 110, 118, 255, 0
db 110, 118, 255, 0
db 110, 118, 255, 0
db 111, 118, 255, 0
db 111, 118, 255, 0
db 111, 119, 255, 0
db 111, 119, 255, 0
db 111, 119, 255, 0
db 112, 119, 255, 0
db 112, 120, 255, 0
db 112, 120, 255, 0
db 112, 120, 255, 0
db 112, 120, 255, 0
db 113, 120, 255, 0
db 113, 121, 255, 0
db 113, 121, 255, 0
db 113, 121, 255, 0
db 113, 121, 255, 0
db 114, 121, 255, 0
db 114, 122, 255, 0
db 114, 122, 255, 0
db 114, 122, 255, 0
db 114, 122, 255, 0
db 115, 122, 255, 0
db 115, 123, 255, 0
db 115, 123, 255, 0
db 115, 123, 255, 0
db 115, 123, 255, 0
db 116, 124, 255, 0
db 116, 124, 255, 0
db 116, 124, 255, 0
db 116, 124, 255, 0
db 116, 124, 255, 0
db 117, 125, 255, 0
db 117, 125, 255, 0
db 117, 125, 255, 0
db 117, 125, 255, 0
db 117, 125, 255, 0
db 118, 126, 255, 0
db 118, 126, 255, 0
db 118, 126, 255, 0
db 118, 126, 255, 0
db 118, 127, 255, 0
db 119, 127, 255, 0
db 119, 127, 255, 0
db 119, 127, 255, 0
db 119, 127, 255, 0
db 119, 128, 255, 0
db 120, 128, 255, 0
db 120, 128, 255, 0
db 120, 128, 255, 0
db 120, 128, 255, 0
db 120, 129, 255, 0
db 121, 129, 255, 0
db 121, 129, 255, 0
db 121, 129, 255, 0
db 121, 130, 255, 0
db 121, 130, 255, 0
db 122, 130, 255, 0
db 122, 130, 255, 0
db 122, 130, 255, 0
db 122, 131, 255, 0
db 122, 131, 255, 0
db 123, 131, 255, 0
db 123, 131, 255, 0
db 123, 131, 255, 0
db 123, 132, 255, 0
db 123, 132, 255, 0
db 124, 132, 255, 0
db 124, 132, 255, 0
db 124, 132, 255, 0
db 124, 133, 255, 0
db 124, 133, 255, 0
db 125, 133, 255, 0
db 125, 133, 255, 0
db 125, 134, 255, 0
db 125, 134, 255, 0
db 125, 134, 255, 0
db 126, 134, 255, 0
db 126, 134, 255, 0
db 126, 135, 255, 0
db 126, 135, 255, 0
db 126, 135, 255, 0
db 127, 135, 255, 0
db 127, 135, 255, 0
db 127, 136, 255, 0
db 127, 136, 255, 0
db 127, 136, 255, 0
db 128, 136, 255, 0
db 128, 137, 255, 0
db 128, 137, 255, 0
db 128, 137, 255, 0
db 128, 137, 255, 0
db 129, 137, 255, 0
db 129, 138, 255, 0
db 129, 138, 255, 0
db 129, 138, 255, 0
db 129, 138, 255, 0
db 130, 138, 255, 0
db 130, 139, 255, 0
db 130, 139, 255, 0
db 130, 139, 255, 0
db 130, 139, 255, 0
db 131, 140, 255, 0
db 131, 140, 255, 0
db 131, 140, 255, 0
db 131, 140, 255, 0
db 131, 140, 255, 0
db 132, 141, 255, 0
db 132, 141, 255, 0
db 132, 141, 255, 0
db 132, 141, 255, 0
db 132, 141, 255, 0
db 133, 142, 255, 0
db 133, 142, 255, 0
db 133, 142, 255, 0
db 133, 142, 255, 0
db 133, 142, 255, 0
db 134, 143, 255, 0
db 134, 143, 255, 0
db 134, 143, 255, 0
db 134, 143, 255, 0
db 134, 144, 255, 0
db 135, 144, 255, 0
db 135, 144, 255, 0
db 135, 144, 255, 0
db 135, 144, 255, 0
db 135, 145, 255, 0
db 136, 145, 255, 0
db 136, 145, 255, 0
db 136, 145, 255, 0
db 136, 145, 255, 0
db 136, 146, 255, 0
db 137, 146, 255, 0
db 137, 146, 255, 0
db 137, 146, 255, 0
db 137, 147, 255, 0
db 137, 147, 255, 0
db 138, 147, 255, 0
db 138, 147, 255, 0
db 138, 147, 255, 0
db 138, 148, 255, 0
db 138, 148, 255, 0
db 139, 148, 255, 0
db 139, 148, 255, 0
db 139, 148, 255, 0
db 139, 149, 255, 0
db 139, 149, 255, 0
db 140, 149, 255, 0
db 140, 149, 255, 0
db 140, 150, 255, 0
db 140, 150, 255, 0
db 140, 150, 255, 0
db 141, 150, 255, 0
db 141, 150, 255, 0
db 141, 151, 255, 0
db 141, 151, 255, 0
db 141, 151, 255, 0
db 142, 151, 255, 0
db 142, 151, 255, 0
db 142, 152, 255, 0
db 142, 152, 255, 0
db 142, 152, 255, 0
db 143, 152, 255, 0
db 143, 153, 255, 0
db 143, 153, 255, 0
db 143, 153, 255, 0
db 143, 153, 255, 0
db 144, 153, 255, 0
db 144, 154, 255, 0
db 144, 154, 255, 0
db 144, 154, 255, 0
db 144, 154, 255, 0
db 145, 154, 255, 0
db 145, 155, 255, 0
db 145, 155, 255, 0
db 145, 155, 255, 0
db 145, 155, 255, 0
db 146, 155, 255, 0
db 146, 156, 255, 0
db 146, 156, 255, 0
db 146, 156, 255, 0
db 146, 156, 255, 0
db 147, 157, 255, 0
db 147, 157, 255, 0
db 147, 157, 255, 0
db 147, 157, 255, 0
db 147, 157, 255, 0
db 148, 158, 255, 0
db 148, 158, 255, 0
db 148, 158, 255, 0
db 148, 158, 255, 0
db 148, 158, 255, 0
db 149, 159, 255, 0
db 149, 159, 255, 0
db 149, 159, 255, 0
db 149, 159, 255, 0
db 149, 160, 255, 0
db 150, 160, 255, 0
db 150, 160, 255, 0
db 150, 160, 255, 0
db 150, 160, 255, 0
db 150, 161, 255, 0
db 151, 161, 255, 0
db 151, 161, 255, 0
db 151, 161, 255, 0
db 151, 161, 255, 0
db 151, 162, 255, 0
db 152, 162, 255, 0
db 152, 162, 255, 0
db 152, 162, 255, 0
db 152, 163, 255, 0
db 152, 163, 255, 0
db 153, 163, 255, 0
db 153, 163, 255, 0
db 153, 163, 255, 0
db 153, 164, 255, 0
db 153, 164, 255, 0
db 153, 164, 255, 0
db 154, 164, 255, 0
db 154, 164, 255, 0
db 154, 165, 255, 0
db 154, 165, 255, 0
db 154, 165, 255, 0
db 155, 165, 255, 0
db 155, 165, 255, 0
db 155, 166, 255, 0
db 155, 166, 255, 0
db 155, 166, 255, 0
db 156, 166, 255, 0
db 156, 167, 255, 0
db 156, 167, 255, 0
db 156, 167, 255, 0
db 156, 167, 255, 0
db 157, 167, 255, 0
db 157, 168, 255, 0
db 157, 168, 255, 0
db 157, 168, 255, 0
db 157, 168, 255, 0
db 158, 168, 255, 0
db 158, 169, 255, 0
db 158, 169, 255, 0
db 158, 169, 255, 0
db 158, 169, 255, 0
db 159, 170, 255, 0
db 159, 170, 255, 0
db 159, 170, 255, 0
db 159, 170, 255, 0
db 159, 170, 255, 0
db 160, 171, 255, 0
db 160, 171, 255, 0
db 160, 171, 255, 0
db 160, 171, 255, 0
db 160, 171, 255, 0
db 161, 172, 255, 0
db 161, 172, 255, 0
db 161, 172, 255, 0
db 161, 172, 255, 0
db 161, 173, 255, 0
db 162, 173, 255, 0
db 162, 173, 255, 0
db 162, 173, 255, 0
db 162, 173, 255, 0
db 162, 174, 255, 0
db 163, 174, 255, 0
db 163, 174, 255, 0
db 163, 174, 255, 0
db 163, 174, 255, 0
db 163, 175, 255, 0
db 164, 175, 255, 0
db 164, 175, 255, 0
db 164, 175, 255, 0
db 164, 175, 255, 0
db 164, 176, 255, 0
db 165, 176, 255, 0
db 165, 176, 255, 0
db 165, 176, 255, 0
db 165, 177, 255, 0
db 165, 177, 255, 0
db 166, 177, 255, 0
db 166, 177, 255, 0
db 166, 177, 255, 0
db 166, 178, 255, 0
db 166, 178, 255, 0
db 167, 178, 255, 0
db 167, 178, 255, 0
db 167, 178, 255, 0
db 167, 179, 255, 0
db 167, 179, 255, 0
db 168, 179, 255, 0
db 168, 179, 255, 0
db 168, 180, 255, 0
db 168, 180, 255, 0
db 168, 180, 255, 0
db 169, 180, 255, 0
db 169, 180, 255, 0
db 169, 181, 255, 0
db 169, 181, 255, 0
db 169, 181, 255, 0
db 170, 181, 255, 0
db 170, 181, 255, 0
db 170, 182, 255, 0
db 170, 182, 255, 0
db 170, 182, 255, 0
db 171, 182, 255, 0
db 171, 183, 255, 0
db 171, 183, 255, 0
db 171, 183, 255, 0
db 171, 183, 255, 0
db 172, 183, 255, 0
db 172, 184, 255, 0
db 172, 184, 255, 0
db 172, 184, 255, 0
db 172, 184, 255, 0
db 173, 184, 255, 0
db 173, 185, 255, 0
db 173, 185, 255, 0
db 173, 185, 255, 0
db 173, 185, 255, 0
db 174, 186, 255, 0
db 174, 186, 255, 0
db 174, 186, 255, 0
db 174, 186, 255, 0
db 174, 186, 255, 0
db 175, 187, 255, 0
db 175, 187, 255, 0
db 175, 187, 255, 0
db 175, 187, 255, 0
db 175, 187, 255, 0
db 176, 188, 255, 0
db 176, 188, 255, 0
db 176, 188, 255, 0
db 176, 188, 255, 0
db 176, 188, 255, 0
db 177, 189, 255, 0
db 177, 189, 255, 0
db 177, 189, 255, 0
db 177, 189, 255, 0
db 177, 190, 255, 0
db 178, 190, 255, 0
db 178, 190, 255, 0
db 178, 190, 255, 0
db 178, 190, 255, 0
db 178, 191, 255, 0
db 179, 191, 255, 0
db 179, 191, 255, 0
db 179, 191, 255, 0
db 179, 191, 255, 0
db 179, 192, 255, 0
db 180, 192, 255, 0
db 180, 192, 255, 0
db 180, 192, 255, 0
db 180, 193, 255, 0
db 180, 193, 255, 0
db 181, 193, 255, 0
db 181, 193, 255, 0
db 181, 193, 255, 0
db 181, 194, 255, 0
db 181, 194, 255, 0
db 182, 194, 255, 0
db 182, 194, 255, 0
db 182, 194, 255, 0
db 182, 195, 255, 0
db 182, 195, 255, 0
db 183, 195, 255, 0
db 183, 195, 255, 0
db 183, 196, 255, 0
db 183, 196, 255, 0
db 183, 196, 255, 0
db 184, 196, 255, 0
db 184, 196, 255, 0
db 184, 197, 255, 0
db 184, 197, 255, 0
db 184, 197, 255, 0
db 185, 197, 255, 0
db 185, 197, 255, 0
db 185, 198, 255, 0
db 185, 198, 255, 0
db 185, 198, 255, 0
db 186, 198, 255, 0
db 186, 198, 255, 0
db 186, 199, 255, 0
db 186, 199, 255, 0
db 186, 199, 255, 0
db 187, 199, 255, 0
db 187, 200, 255, 0
db 187, 200, 255, 0
db 187, 200, 255, 0
db 187, 200, 255, 0
db 188, 200, 255, 0
db 188, 201, 255, 0
db 188, 201, 255, 0
db 188, 201, 255, 0
db 188, 201, 255, 0
db 189, 201, 255, 0
db 189, 202, 255, 0
db 189, 202, 255, 0
db 189, 202, 255, 0
db 189, 202, 255, 0
db 190, 203, 255, 0
db 190, 203, 255, 0
db 190, 203, 255, 0
db 190, 203, 255, 0
db 190, 203, 255, 0
db 191, 204, 255, 0
db 191, 204, 255, 0
db 191, 204, 255, 0
db 191, 204, 255, 0
db 191, 204, 255, 0
db 192, 205, 255, 0
db 192, 205, 255, 0
db 192, 205, 255, 0
db 192, 205, 255, 0
db 192, 206, 255, 0
db 193, 206, 255, 0
db 193, 206, 255, 0
db 193, 206, 255, 0
db 193, 206, 255, 0
db 193, 207, 255, 0
db 194, 207, 255, 0
db 194, 207, 255, 0
db 194, 207, 255, 0
db 194, 207, 255, 0
db 194, 208, 255, 0
db 195, 208, 255, 0
db 195, 208, 255, 0
db 195, 208, 255, 0
db 195, 208, 255, 0
db 195, 209, 255, 0
db 196, 209, 255, 0
db 196, 209, 255, 0
db 196, 209, 255, 0
db 196, 210, 255, 0
db 196, 210, 255, 0
db 197, 210, 255, 0
db 197, 210, 255, 0
db 197, 210, 255, 0
db 197, 211, 255, 0
db 197, 211, 255, 0
db 198, 211, 255, 0
db 198, 211, 255, 0
db 198, 211, 255, 0
db 198, 212, 255, 0
db 198, 212, 255, 0
db 199, 212, 255, 0
db 199, 212, 255, 0
db 199, 213, 255, 0
db 199, 213, 255, 0
db 199, 213, 255, 0
db 200, 213, 255, 0
db 200, 213, 255, 0
db 200, 214, 255, 0
db 200, 214, 255, 0
db 200, 214, 255, 0
db 201, 214, 255, 0
db 201, 214, 255, 0
db 201, 215, 255, 0
db 201, 215, 255, 0
db 201, 215, 255, 0
db 202, 215, 255, 0
db 202, 216, 255, 0
db 202, 216, 255, 0
db 202, 216, 255, 0
db 202, 216, 255, 0
db 203, 216, 255, 0
db 203, 217, 255, 0
db 203, 217, 255, 0
db 203, 217, 255, 0
db 203, 217, 255, 0
db 204, 217, 255, 0
db 204, 218, 255, 0
db 204, 218, 255, 0
db 204, 218, 255, 0
db 204, 218, 255, 0
palette_size: equ ($-palette) 
	

section		.bss

	arrayPtr	resb IMAGE_SIZE
	pi			resq 1
	pr			resq 1

	oldRe 		resq 1
	oldIm 		resq 1
	newRe 		resq 1
	newIm 		resq 1

	
