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
    BSR     DRAW_FULL_ROCKET

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
* PHASE 1: FLIGHT (ascent)
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
    ; Clear screen on transition so rocket ghost is gone before docking starts
    BSR     CLEAR_SCREEN
    MOVE.B  #2,STATE
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 2: DOCKING
*-------------------------------------------------------
DO_DOCK:
    BSR     ERASE_CSM
    BSR     ERASE_LM

    ; Draw CSM
    MOVE.W  CSM_X,D4
    MOVE.W  #CSM_ROW,D3
    LEA     PTR_CSM,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE

    ; Draw LM
    MOVE.W  LM_X,D4
    MOVE.W  #LM_ROW,D3
    LEA     PTR_LM_UP,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE

    ; Erase old dock msg before printing new one so it never doubles up
    MOVE.W  #$1500,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANK_DOCK,A1
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.W  #$1500,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     DOCK_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.B  #18,D0
    TRAP    #15

    CMP.L   #1,D1
    BEQ     M_L
    CMP.L   #2,D1
    BEQ     M_R
    CMP.L   #3,D1
    BEQ     M_D
    BRA     DO_DOCK

M_L:
    CMP.W   #0,CSM_X
    BLE     DO_DOCK
    SUBQ.W  #5,CSM_X
    BRA     DO_DOCK
M_R:
    CMP.W   #71,CSM_X
    BGE     DO_DOCK
    ADDQ.W  #5,CSM_X
    BRA     DO_DOCK
M_D:
    MOVE.W  CSM_X,D0
    SUB.W   LM_X,D0
    BSR     ABS
    CMP.W   #5,D0
    BLE     D_OK
    BRA     DO_DOCK

D_OK:
    CLR.W   DOCKED_ALT
    MOVE.B  #3,STATE
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

    MOVE.W  #4,D3
    LEA     PTR_LM_UP,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE

    MOVE.W  #9,D3
    LEA     PTR_CSM,A0
    MOVE.W  #5,D2
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
DRAW_FULL_ROCKET:
    LEA     PTR_SATURN,A0
    MOVE.W  #15,D2
    MOVE.W  #35,D4
    BSR     DRAW_SPRITE
    RTS

DRAW_UPPER_STAGE:
    LEA     PTR_UPPER,A0
    MOVE.W  #8,D2
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
    MOVE.W  #15,D2
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

ERASE_CSM:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  CSM_X,D4
    MOVE.W  #CSM_ROW,D3
    MOVE.W  #SPRITE_H,D2
ER_CSM_L:
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
    BNE     ER_CSM_L
    MOVEM.L (A7)+,D0-D5/A0-A1
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
PROMPT_LAUNCH:  DC.B    '1 + ENTER TO LAUNCH!',0
DOCK_MSG:       DC.B    '1=LEFT  2=RIGHT  3=DOCK',0
BLANK_DOCK:     DC.B    '                       ',0   ;
BLANKLINE_WIDE: DC.B    '            ',0

PTR_SATURN: DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15
PTR_UPPER:  DC.L S1,S2,S3,S4,S5,S6,S14,S15
PTR_CSM:    DC.L C1,C2,C3,C4,C5
PTR_LM_UP:  DC.L U1,U2,U3,U4,U5

S1:  DC.B '     ^     ',0
S2:  DC.B '    / \    ',0
S3:  DC.B '   |   |   ',0
S4:  DC.B '   |   |   ',0
S5:  DC.B '   |   |   ',0
S6:  DC.B '   |---|   ',0
S7:  DC.B '   |   |   ',0
S8:  DC.B '   |   |   ',0
S9:  DC.B '   |---|   ',0
S10: DC.B '  /|   |\  ',0
S11: DC.B ' | |USA| | ',0
S12: DC.B ' |_|   |_| ',0
S13: DC.B '   |___|   ',0
S14: DC.B '    / \    ',0
S15: DC.B '   V V V   ',0

C1: DC.B '   /\   ',0
C2: DC.B '  /  \  ',0
C3: DC.B ' |    | ',0
C4: DC.B ' |____| ',0
C5: DC.B '  /__\  ',0

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