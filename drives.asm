/* DRIVES.EXE - compact DOS drive indicator, GNU as (i386) source. */
.code16
.intel_syntax noprefix
.global _start

.equ WHITE,  0x0f
.equ GREEN,  0x0a
.equ GREY,   0x08

.text
_start:
        push cs
        pop  ds

        /* Suppress DOS critical-error prompts while enumerating drives.
           Save the caller's INT 24h vector and temporarily return Fail. */
        mov  ax, 0x3524
        int  0x21
        mov  word ptr [old24_off], bx
        mov  word ptr [old24_seg], es
        mov  dx, offset critical_error
        mov  ax, 0x2524
        int  0x21

        xor  dx, dx                  /* DL = drive number, A: = 0 */

drive_loop:
        push dx
        call classify_drive          /* AL = symbol, or zero if absent */
        pop  dx
        test al, al
        jz   next_drive

        mov  byte ptr [symbol], al
        mov  al, '['
        mov  bl, WHITE
        call putc
        mov  al, dl
        add  al, 'A'
        mov  bl, GREEN
        call putc
        mov  al, ':'
        mov  bl, GREEN
        call putc
        mov  al, ' '
        mov  bl, WHITE
        call putc
        mov  al, byte ptr [symbol]
        mov  bl, GREY
        call putc
        mov  al, ']'
        mov  bl, WHITE
        call putc
        mov  al, ' '
        mov  bl, WHITE
        call putc

next_drive:
        inc  dl
        cmp  dl, 26
        jb   drive_loop
        mov  al, 13
        mov  bl, WHITE
        call putc
        mov  al, 10
        call putc

        /* Restore the original DOS critical-error handler. */
        push ds
        lds  dx, dword ptr [old24_off]
        mov  ax, 0x2524
        int  0x21
        pop  ds

        mov  ax, 0x4c00
        int  0x21

/* Input DL=0..25. Output AL=CP437 symbol, zero if drive is unavailable. */
classify_drive:
        push bx
        push cx
        push dx
        push si
        push es
        mov  byte ptr [drive_no], dl

        /* Never probe floppy media.  INT 11h reports the installed BIOS
           floppy count in bits 6-7 when bit 0 is set. */
        cmp  dl, 2
        jae  check_cd
        int  0x11
        test al, 1
        jz   absent
        shr  al, 6
        and  al, 3
        inc  al
        mov  bl, byte ptr [drive_no]
        cmp  bl, al
        jae  absent
        mov  al, '-'
        jmp  classified

        /* MSCDEX installation check and per-drive CD-ROM query. */
check_cd:
        mov  ax, 0x1500
        xor  bx, bx
        int  0x2f
        test bx, bx
        jz   not_cd
        xor  ch, ch
        mov  cl, byte ptr [drive_no] /* INT 2Fh need not preserve DX */
        mov  ax, 0x150b
        int  0x2f
        cmp  bx, 0xadad
        jne  not_cd
        test ax, ax
        jz   not_cd
        mov  al, 9                   /* CP437 white circle */
        jmp  classified

not_cd:
        /* DOS IOCTL: valid drive, and remote/redirected drive flag. */
        mov  bl, byte ptr [drive_no]
        inc  bl
        mov  ax, 0x4409
        int  0x21
        jc   absent
        test dh, 0x10                /* DX bit 12 = remote */
        jz   local_drive
        mov  al, 18                  /* CP437 up/down arrow */
        jmp  classified

local_drive:
        /* Obtain DPB and inspect its block-driver header name. */
        push ds
        push bx
        mov  dl, bl
        mov  ah, 0x32
        int  0x21
        cmp  al, 0xff
        je   dpb_done
        mov  si, word ptr [bx+0x13]
        mov  ax, word ptr [bx+0x15]
        mov  es, ax
        add  si, 0x0a                /* 8-byte device name */
        mov  ax, es:[si]
        and  ax, 0xdfdf              /* ASCII uppercase */
        cmp  ax, 0x4152              /* RA... (RAMDRIVE/RAMDISK) */
        je   ram_found
        cmp  ax, 0x4456              /* VD... (VDISK) */
        je   ram_found
        cmp  ax, 0x4d58              /* XM... (XMSDSK) */
        je   ram_found
        cmp  ax, 0x5253              /* SR... (SRDISK) */
        je   ram_found
        cmp  ax, 0x4454              /* TD... (TDSK) */
        je   ram_found
        cmp  ax, 0x5224              /* $R... (MS RAMDRIVE.SYS) */
        je   ram_found
dpb_done:
        pop  bx
        pop  ds

        /* RAM-disk utilities commonly advertise themselves in the volume
           label even when their DOS block device looks like a fixed disk. */
        call ram_volume_label
        test al, al
        jnz  ram_classified

        /* Removable local media are represented by the floppy symbol. */
        mov  dl, bl
        mov  ax, 0x4408
        int  0x21
        jc   fixed_drive
        test ax, ax
        jnz  fixed_drive
        mov  al, '-'
        jmp  classified
fixed_drive:
        mov  al, 240                 /* CP437 triple horizontal bar */
        jmp  classified

ram_classified:
        mov  al, '#'
        jmp  classified

ram_found:
        pop  bx
        pop  ds
        mov  al, '#'
        jmp  classified
absent:
        xor  al, al
classified:
        pop  es
        pop  si
        pop  dx
        pop  cx
        pop  bx
        ret

/* AL=1 for common RAM-disk volume labels, otherwise AL=0. */
ram_volume_label:
        push bx
        push cx
        push dx
        push si
        mov  ah, 0x1a                /* set our private DTA */
        mov  dx, offset dta
        int  0x21
        mov  al, byte ptr [drive_no]
        add  al, 'A'
        mov  byte ptr [label_mask], al
        mov  dx, offset label_mask
        mov  cx, 8                   /* volume-label attribute */
        mov  ah, 0x4e
        int  0x21
        jc   label_no
        mov  si, offset dta+30       /* ASCIIZ name in DOS find DTA */
        mov  ax, word ptr [si]
        and  ax, 0xdfdf
        cmp  ax, 0x4152              /* RA... RAMDRIVE */
        je   label_yes
        cmp  ax, 0x4452              /* RD... RDV-386DSK */
        je   label_yes
        cmp  ax, 0x4d58              /* XM... XMSDISK */
        je   label_yes
        cmp  ax, 0x534d              /* MS... MS-RAMDRIVE */
        jne  label_no
        cmp  byte ptr [si+2], '-'
        jne  label_no
        mov  ax, word ptr [si+3]
        and  ax, 0xdfdf
        cmp  ax, 0x4152
        jne  label_no
label_yes:
        mov  al, 1
        jmp  label_done
label_no:
        xor  al, al
label_done:
        pop  si
        pop  dx
        pop  cx
        pop  bx
        ret

/* BIOS writes one colored character and advances the cursor. */
putc:
        push ax
        push bx
        push cx
        push dx
        cmp  al, 32
        jb   putc_control
        mov  ah, 0x09
        xor  bh, bh
        mov  cx, 1
        int  0x10
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        jmp  putc_teletype
putc_control:
        pop  dx
        pop  cx
        pop  bx
        pop  ax
putc_teletype:
        push bx
        push dx
        mov  ah, 0x0e
        xor  bh, bh
        int  0x10
        pop  dx
        pop  bx
        ret

/* DOS INT 24h critical-error handler: fail the operation silently. */
critical_error:
        mov  al, 3
        iret

symbol: .byte 0
drive_no: .byte 0
old24_off: .word 0
old24_seg: .word 0
label_mask: .asciz "A:\\*.*"
.balign 2
dta: .space 43
