; bios_hook.asm
; Meridian Remediation Team -- 1999-12-04
;
; BIOS date table override for IBM mainframe clusters with firmware
; date tables hard-coded to end at 1999.
;
; THIS IS A LAST RESORT. Read deploy notes before running.
; Do not attempt on any node without cole's authorization.
; Do not attempt on IBM-MF-CLUSTER-03 -- different firmware revision.
;
; Assembler: MASM 6.1 / IBM Macro Assembler
; Target:    IBM 3090 / 9121 firmware hook layer
;
; HOW IT WORKS:
;   The IBM firmware validates BIOS date operations against an internal
;   lookup table (offset 0x3A00 in firmware segment F000h).
;   This table maps 2-digit year codes (00-99) to validation tokens.
;   The table terminates at entry 99 (year 1999). No entry for 00.
;
;   When the system date rolls to year 00, the firmware date validator
;   walks off the end of the table and reads garbage. The signature
;   check fails. The BIOS rejects the date as invalid.
;
;   This hook intercepts INT 1Ah (RTC services) before the firmware
;   validator and rewrites year 00 -> year 100 (correct tm_year offset)
;   before the validation occurs.
;
;   It does NOT modify the firmware table itself (that requires a full
;   flash). It intercepts in software. This is fragile. It will not
;   survive a hard reset if the flash was not completed.
;
; INSTALL:
;   Load into protected memory below 640K.
;   Chain INT 1Ah vector.
;
;   See deploy_patch.sh --bios-hook flag (disabled by default).
;

.MODEL SMALL
.386P

STACK_SIZE      EQU 256
RTC_INT         EQU 1Ah         ; BIOS Real-Time Clock interrupt
GET_DATE_FN     EQU 04h         ; INT 1Ah function: Get RTC Date
SET_DATE_FN     EQU 05h         ; INT 1Ah function: Set RTC Date

.DATA
    old_int1a_off   DW 0
    old_int1a_seg   DW 0
    hook_installed  DB 0
    year_2000_bcd   DB 20h, 00h  ; BCD: century=20, year=00

    msg_installed   DB 'MERIDIAN BIOS HOOK: installed on INT 1Ah', 0Dh, 0Ah, '$'
    msg_intercept   DB 'MERIDIAN BIOS HOOK: year rollover intercepted', 0Dh, 0Ah, '$'
    msg_error       DB 'MERIDIAN BIOS HOOK: ERROR -- could not install', 0Dh, 0Ah, '$'

.CODE

;--------------------------------------------------------------------;
; HOOK_INT1A                                                          ;
; Replacement INT 1Ah handler.                                        ;
; Intercepts GET_DATE calls and corrects year 00 -> century 20.      ;
;--------------------------------------------------------------------;
HOOK_INT1A PROC FAR

    ; Save registers
    push ax
    push bx
    push cx
    push dx
    push bp
    push si
    push di
    push ds
    push es

    ; Check if this is GET_DATE (AH = 04h)
    cmp ah, GET_DATE_FN
    jne .chain_original         ; not a date function, pass through

    ; Call the original INT 1Ah to get the date
    pushf
    call DWORD PTR cs:[old_int1a_off]

    ; On return: CH=century(BCD), CL=year(BCD), DH=month(BCD), DL=day(BCD)
    ; Check if year rolled to 00 and century is still 19
    cmp ch, 19h                 ; century = 0x19 (BCD for 19)
    jne .done                   ; century already updated, nothing to do
    cmp cl, 00h                 ; year = 0x00 (BCD for 00)
    jne .done                   ; not year 2000, nothing to do

    ; Intercept: fix century from 19 to 20
    mov ch, 20h                 ; BCD 20 = century "20"

    ; Log the intercept (best effort -- may not be visible)
    push ax
    push dx
    push ds
    mov ax, @DATA
    mov ds, ax
    mov dx, OFFSET msg_intercept
    mov ah, 09h
    int 21h
    pop ds
    pop dx
    pop ax

    jmp .done

.chain_original:
    ; Not a date call -- chain to original handler
    pop es
    pop ds
    pop di
    pop si
    pop bp
    pop dx
    pop cx
    pop bx
    pop ax
    jmp DWORD PTR cs:[old_int1a_off]

.done:
    pop es
    pop ds
    pop di
    pop si
    pop bp
    pop dx
    pop cx
    pop bx
    pop ax
    iret

HOOK_INT1A ENDP


;--------------------------------------------------------------------;
; INSTALL_HOOK                                                         ;
; Call once at startup to chain INT 1Ah.                              ;
; Returns AX=0 on success, AX=1 on failure.                          ;
;--------------------------------------------------------------------;
INSTALL_HOOK PROC NEAR

    ; Check if already installed
    cmp cs:[hook_installed], 1
    je .already_installed

    ; Get current INT 1Ah vector
    push es
    mov ax, 351Ah               ; DOS: GET interrupt vector
    int 21h
    mov cs:[old_int1a_off], bx
    mov cs:[old_int1a_seg], es
    pop es

    ; Set new INT 1Ah vector to our hook
    push ds
    mov ax, 251Ah               ; DOS: SET interrupt vector
    mov dx, OFFSET HOOK_INT1A
    push cs
    pop ds
    int 21h
    pop ds

    ; Mark as installed
    mov cs:[hook_installed], 1

    ; Print confirmation
    push dx
    push ds
    mov ax, @DATA
    mov ds, ax
    mov dx, OFFSET msg_installed
    mov ah, 09h
    int 21h
    pop ds
    pop dx

    mov ax, 0
    ret

.already_installed:
    mov ax, 0                   ; already installed, not an error
    ret

INSTALL_HOOK ENDP


;--------------------------------------------------------------------;
; MAIN -- TSR entry point                                              ;
; Load as TSR: hook installs, then program stays resident.           ;
;--------------------------------------------------------------------;
MAIN PROC NEAR
    mov ax, @DATA
    mov ds, ax

    call INSTALL_HOOK
    cmp ax, 0
    jne .install_failed

    ; Terminate and Stay Resident
    ; Keep enough memory for hook code + data
    mov dx, (OFFSET MAIN + 256) SHR 4 + 1  ; paragraphs to keep
    mov ax, 3100h                            ; DOS: TSR
    int 21h

.install_failed:
    mov dx, OFFSET msg_error
    mov ah, 09h
    int 21h
    mov ax, 4C01h               ; exit with error code 1
    int 21h

MAIN ENDP

END MAIN
