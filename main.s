	IMAGE_WIDTH 	equ 640
	IMAGE_HEIGHT 	equ 480
	IMAGE_DEPTH		equ	3
	IMAGE_SIZE		equ IMAGE_WIDTH * IMAGE_HEIGHT * IMAGE_DEPTH
	MAX_ITER		equ	1000
	
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

setPixel:
	;; R9 	X
	;; R10 	Y
	;; R14 	iter
	
	mov eax,r10d 				; Load Y
	mov r15d, IMAGE_WIDTH		; Load Image Width
	mul r15d
	mov r15d, IMAGE_DEPTH		; Load Image depth (bytes per pixel)
	mul r15d					; Y * width * depth
	mov r8d,eax
	mov eax,r9d					;
	mul r15d					; X * width
	add eax,r8d					; (X * DEPTH) + (Y * WIDTH * DEPTH)
		
	mov [arrayPtr + eax],r14b
	shr r14,8
	mov [arrayPtr + eax+1],r14b
	shr r14,8
	mov [arrayPtr + eax+2],r14b

	ret
	
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
prd:	
	
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
pid:	
	
	mov qword [newIm], 0
	mov qword [newRe], 0 
	mov qword [oldIm], 0
	mov qword [oldRe], 0	

	xor ax,ax
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
	
	cdq						
	mov ecx,256
	idiv ecx
	
	xor r14,r14
	mov r14,rdx
	
	call setPixel
		
	add r9d,1
	cmp r9d,IMAGE_WIDTH
	jne loopY
	xor r9d,r9d
	
	
	add r10d,1
	cmp	r10d,IMAGE_HEIGHT
	jne loopY
	
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
	moveX	dq -0.5
	moveY	dq 0
	zoom	dq 1
	
	msg 	db  'Generating fractal !',0xa
	len 	equ $ - msg                   

	fileName	db 'fractal.data',0x0
	fileNameLen equ $ - fileName

	oneHalf	dq 1.5
	half	dq 0.5

section		.bss

	arrayPtr	resb IMAGE_SIZE
	pi			resq 1
	pr			resq 1

	oldRe 		resq 1
	oldIm 		resq 1
	newRe 		resq 1
	newIm 		resq 1

	
