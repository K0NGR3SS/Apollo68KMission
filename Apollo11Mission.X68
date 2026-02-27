*-----------------------------------------------------------
* Title      : Apollo 11 Mission
* Written by : Nazariy Buryak
* Date       : 18/02/2025
* Description: Apollo 11 Mission
*-----------------------------------------------------------

    ORG $1000

*--- CONSTANTS ---
PAD_STATE   EQU 0
FLY_STATE   EQU 1
DOCK_STATE  EQU 2
FLY_DOCKED  EQU 3

CSM_ROW     EQU 10
LM_ROW      EQU 5
SPRITE_H    EQU 5

*-------------------------------------------------------
* VARIABLES
*-------------------------------------------------------
    ORG $4000

ALT:        DC.W    0
STATE:      DC.B    0
            DS.B    1
CSM_X:      DC.W    10
OLD_CSM_X:  DC.W    10
CSM_Y:      DC.W    12
OLD_CSM_Y   DC.W    12
LM_X:       DC.W    40
DOCKED_ALT: DC.W    0


*-------------------------------------------------------
* START
*-------------------------------------------------------
    ORG $1000
START:
    BSR     CLEAR_SCREEN

MAIN_LOOP:
    MOVE.B  STATE,D0
    CMP.B   #PAD_STATE,D0
    BEQ     DO_PAD
    CMP.B   #FLY_STATE,D0
    BEQ     DO_FLY
    CMP.B   #DOCK_STATE,D0
    BEQ     DO_DOCK
    CMP.B   #FLY_DOCKED,D0
    BEQ     DO_FLY_DOCKED
    BRA     END_GAME

*-------------------------------------------------------
* PHASE 0: PRE-LAUNCH
*-------------------------------------------------------
DO_PAD:
    BSR     CLEAR_SCREEN
    BSR     SHOW_STATS
    BSR     DRAW_STARS
    MOVE.W  #5,D3
    BSR     DRAW_PAD_ROCKET

    MOVE.W  #$1402,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     PROMPT_LAUNCH,A1
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.B  #18,D0
    TRAP    #15
    ; Clear screen on transition so launch prompt is gone before flight starts
    BSR     CLEAR_SCREEN
    MOVE.B  #1,STATE
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 1: FLIGHT
*-------------------------------------------------------
DO_FLY:
    BSR     SHOW_STATS
    ADDQ.W  #1,ALT
    BSR     ERASE_ROCKET
    BSR     DRAW_STARS
    MOVE.W  #5,D3
    MOVE.W  ALT,D0
    CMP.W   #45,D0
    BGT     FLY_SEP
    BSR     DRAW_FULL_ROCKET
    BRA     FLY_STARS
FLY_SEP:
    BSR     ERASE_ROCKET
    BSR     DRAW_UPPER_STAGE
FLY_STARS:
    MOVE.L  #4,D1
    MOVE.B  #23,D0
    TRAP    #15
    MOVE.W  ALT,D0
    CMP.W   #80,D0
    BGE     GO_DOCK
    BRA     DO_FLY
GO_DOCK:
    BSR     ERASE_UPPER_STAGE  
    BSR     CLEAR_SCREEN
    MOVE.B  #DOCK_STATE,STATE
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 2: DOCKING
*-------------------------------------------------------
DO_DOCK:

    BSR     CLEAR_SCREEN        ; Clear Stage 1 rocket remnants

DOCK_LOOP:
    BSR     SHOW_STATS          ; Keep altitude visible
    
    ; Erase old position
    MOVE.W  OLD_CSM_X, D4
    MOVE.W  OLD_CSM_Y, D3
    BSR     ERASE_CSM
    
    ; Draw LM (Static)
    MOVE.W  LM_X, D4
    MOVE.W  #LM_ROW, D3
    LEA     PTR_LM_UP, A0
    MOVE.W  #SPRITE_H, D2
    BSR     DRAW_SPRITE

    ; Draw CSM (Moving)
    MOVE.W  CSM_X, D4
    MOVE.W  CSM_Y, D3
    LEA     PTR_CSM, A0
    MOVE.W  #SPRITE_H, D2
    BSR     DRAW_SPRITE

    MOVE.W  #$1500, D1          ; Position for instructions
    MOVE.B  #11, D0
    TRAP    #15
    
    LEA     DOCK_MSG, A1
    MOVE.B  #14, D0
    TRAP    #15

    MOVE.B  #18, D0             ; Read keyboard (Wait for key)
    TRAP    #15                 ; Result in D1

    ; Store current as "old" before updating
    MOVE.W  CSM_X, OLD_CSM_X
    MOVE.W  CSM_Y, OLD_CSM_Y

    CMP.L   #$1B, D1            ; Check for ESC or specific keys

    CMP.B   #1, D1
    BEQ     M_U

    CMP.B   #2, D1
    BEQ     M_S

    CMP.B   #3, D1
    BEQ     M_L

    CMP.B   #4, D1
    BEQ     M_R

    CMP.B   #5,  D1
    BEQ     M_D

    BRA     DOCK_LOOP   
    
M_L:
    SUBQ.W  #2, CSM_X
    BRA     DOCK_LOOP

M_R:
    ADDQ.W  #2, CSM_X
    BRA     DOCK_LOOP

M_U:
    SUBQ.W  #1, CSM_Y
    BRA     DOCK_LOOP

M_S:
    ADDQ.W  #1, CSM_Y           ;M_S is move down, just using M_D as docking
    BRA     DOCK_LOOP

M_D:
    MOVE.W  CSM_X, D0
    SUB.W   LM_X, D0
    BSR     ABS
    CMP.W   #3, D0              ; Tolerance
    BGT     DOCK_LOOP           ; Too far
    MOVE.W  CSM_Y, D0

    SUB.W   #LM_ROW+5, D0       ; Check if bottom of LM meets top of CSM
    BSR     ABS
    CMP.W   #1, D0
    BLE     D_OK
    BRA     DOCK_LOOP

D_OK:
    CLR.W   DOCKED_ALT
    MOVE.B  #3, STATE
    BRA     MAIN_LOOP
    
*-------------------------------------------------------
* PHASE 3: JOINT FLIGHT
*-------------------------------------------------------
DO_FLY_DOCKED:
    TST.W   DOCKED_ALT
    BNE     DFD_SKIP_CLEAR
    BSR     CLEAR_SCREEN
DFD_SKIP_CLEAR:

    BSR     SHOW_STATS
    ADDQ.W  #1,ALT
    ADDQ.W  #1,DOCKED_ALT

    BSR     ERASE_JOINT
    BSR     DRAW_STARS
    BSR     DRAW_JOINT

    MOVE.L  #4,D1
    MOVE.B  #23,D0
    TRAP    #15

    MOVE.W  DOCKED_ALT,D0
    CMP.W   #50,D0
    BGE     END_GAME
    BRA     DO_FLY_DOCKED

DRAW_JOINT:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #30,D4

    MOVE.W  #5,D3
    LEA     PTR_LM_UP,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE

    MOVE.W  #9,D3
    LEA     PTR_CSM_FLY,A0
    MOVE.W  #6,D2
    BSR     DRAW_SPRITE

    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

ERASE_JOINT:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #30,D4
    MOVE.W  #4,D3
    MOVE.W  #10,D2
EJ_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     EJ_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-------------------------------------------------------
* RENDERING SUBROUTINES
*-------------------------------------------------------
DRAW_PAD_ROCKET:
    LEA     PTR_SATURN,A0
    MOVE.W  #18,D2
    MOVE.W  #35,D4
    BSR     DRAW_SPRITE
    RTS
DRAW_FULL_ROCKET:
    LEA     PTR_SATURN,A0
    MOVE.W  #19,D2
    MOVE.W  #35,D4
    BSR     DRAW_SPRITE
    RTS

DRAW_UPPER_STAGE:
    LEA     PTR_UPPER,A0
    MOVE.W  #11,D2
    MOVE.W  #35,D4
    BSR     DRAW_SPRITE
    RTS

DRAW_SPRITE:
    MOVEM.L D0-D5/A0-A1,-(A7)
DS_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.L  (A0)+,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     DS_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

ERASE_ROCKET:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #35,D4
    MOVE.W  #5,D3
    MOVE.W  #19,D2
    LEA     BLANKLINE_WIDE,A1
ER_R:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_R
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS
    
ERASE_UPPER_STAGE:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #35,D4              ; Same X as DRAW_UPPER_STAGE
    MOVE.W  #5,D3               ; Starting Row
    MOVE.W  #11,D2               ; Height of upper stage
    LEA     BLANKLINE_WIDE,A1
ER_UP_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0              ; Cursor Pos
    TRAP    #15
    MOVE.B  #14,D0              ; Print Blanks
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_UP_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS
    
ERASE_CSM:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  OLD_CSM_X, D4       ; Use the OLD X
    MOVE.W  OLD_CSM_Y, D3       ; Use the OLD Y
    MOVE.W  #SPRITE_H, D2
    LEA     BLANKLINE_WIDE, A1
ER_CSM_L:
    MOVE.W  D4, D1
    LSL.W   #8, D1
    OR.B    D3, D1
    MOVE.B  #11, D0             ; Set Cursor
    TRAP    #15
    MOVE.B  #14, D0             ; Print Blanks
    TRAP    #15
    ADDQ.W  #1, D3
    SUBQ.W  #1, D2
    BNE     ER_CSM_L
    MOVEM.L (A7)+, D0-D5/A0-A1
    RTS
    
ERASE_LM:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  LM_X,D4
    MOVE.W  #LM_ROW,D3
    MOVE.W  #SPRITE_H,D2
    LEA     BLANKLINE_WIDE,A1
ER_LM_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_LM_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

DRAW_STARS:
    MOVE.W  #$0502,D1
    BSR     P_S
    MOVE.W  #$350A,D1
    BSR     P_S
    RTS
P_S:
    MOVE.B  #11,D0
    TRAP    #15
    LEA     STAR,A1
    MOVE.B  #14,D0
    TRAP    #15
    RTS

CLEAR_SCREEN:
    MOVE.B  #12,D0
    TRAP    #15
    RTS

SHOW_STATS:
    MOVE.W  #$0014,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     ALT_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  ALT,D1
    EXT.L   D1
    MOVE.B  #3,D0
    TRAP    #15
    RTS

ABS:
    TST.W   D0
    BPL     A_X
    NEG.W   D0
A_X:
    RTS

END_GAME:
    MOVE.B  #9,D0
    TRAP    #15

*-------------------------------------------------------
* DATA
*-------------------------------------------------------
STAR:           DC.B    '*',0
ALT_MSG:        DC.B    'ALTITUDE: ',0
PROMPT_LAUNCH:  DC.B    '1 to Lift Off!',0
DOCK_MSG:       DC.B    'Move with Numbers',0
BLANK_DOCK:     DC.B    '                            ',0
BLANKLINE_WIDE: DC.B    '                    ',0

PTR_SATURN: DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15,S16,S17,S18,S19
PTR_UPPER:  DC.L S2,S3,S4,S5,S6,S7,S8,S9,S10,S18,S19
PTR_CSM:    DC.L C1,C2,C3,C4,C5
PTR_CSM_FLY: DC.L C1,C2,C3,C4,C5,C6
PTR_LM_UP:  DC.L U1,U2,U3,U4,U5

S1:  DC.B '     |     ',0
S2:  DC.B '     !     ',0
S3:  DC.B '    / \    ',0
S4:  DC.B '   |   |   ',0
S5:  DC.B '   |   |   ',0
S6:  DC.B '   |   |   ',0
S7:  DC.B '   |   |   ',0
S8:  DC.B '   |   |   ',0
S9:  DC.B '   |   |   ',0
S10: DC.B '   |---|   ',0
S11: DC.B '   | | |   ',0
S12: DC.B '   | | |   ',0
S13: DC.B '   | | |   ',0
S14: DC.B '   | | |   ',0
S15: DC.B '   | U |   ',0
S16: DC.B '  /| S |\  ',0
S17: DC.B ' |_|_A_|_| ',0
S18: DC.B '   /\|/\   ',0
S19: DC.B '   V V V   ',0

C1: DC.B '   /\   ',0
C2: DC.B '  /  \  ',0
C3: DC.B ' |    | ',0
C4: DC.B ' |____| ',0
C5: DC.B '  /__\  ',0
C6: DC.B '   VV   ',0

U1: DC.B ' \ __ / ',0
U2: DC.B ' _|__|_ ',0
U3: DC.B ' [    ] ',0
U4: DC.B '  \__/  ',0
U5: DC.B '   ''   ',0

    END START
*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~