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
LAND_STATE  EQU 3

*-------------------------------------------------------
* VARIABLES
*-------------------------------------------------------
    ORG $4000
ALT:        DC.W    0
STATE:      DC.B    0
    DS.B    1
CSM_X:      DC.W    10
LM_X:       DC.W    40
LAND_Y:     DC.W    2
LAND_VY:    DC.W    0

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
    CMP.B   #LAND_STATE,D0
    BEQ     DO_LAND
    BRA     END_GAME

*-------------------------------------------------------
* PHASE 0: PRE-LAUNCH
*-------------------------------------------------------
DO_PAD:
    BSR     DRAW_STARS
    MOVE.W  #5,D3           ; Fixed Row 5
    BSR     DRAW_FULL_ROCKET
    
    MOVE.W  #$1402,D1       ; Row 20, Col 2
    MOVE.B  #11,D0
    TRAP    #15
    LEA     PROMPT_LAUNCH,A1
    MOVE.B  #14,D0
    TRAP    #15
    
    MOVE.B  #18,D0          
    TRAP    #15
    MOVE.B  #1,STATE        
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 1: FLIGHT
*-------------------------------------------------------
DO_FLY:
    BSR     CLEAR_SCREEN
    ADDQ.W  #1,ALT
    
    ; Keeps rocket at Row 5 so it's ALWAYS visible
    MOVE.W  #5,D3
    MOVE.W  ALT,D0
    CMP.W   #10,D0
    BGT     FLY_SEP 
    BSR     DRAW_FULL_ROCKET
    BRA     FLY_STARS
FLY_SEP:
    BSR     DRAW_UPPER_STAGE

FLY_STARS:
    BSR     DRAW_STARS      ; Stars give the illusion of speed
    BSR     SHOW_STATS
    
    MOVE.L  #4,D1           
    MOVE.B  #23,D0
    TRAP    #15
    
    MOVE.W  ALT,D0
    CMP.W   #20,D0          ; Reach orbit at 20
    BGE     GO_DOCK
    BRA     DO_FLY

GO_DOCK:
    MOVE.B  #2,STATE
    BRA     MAIN_LOOP
*-------------------------------------------------------
* PHASE 2: DOCKING
*-------------------------------------------------------
DO_DOCK:
    BSR     CLEAR_SCREEN
    LEA     DOCK_MSG,A1
    BSR     PRINT_STATUS_LINE
    
    ; CSM (Player)
    MOVE.W  CSM_X,D4
    MOVE.W  #8,D3
    LEA     PTR_CSM,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE
    
    ; LM (Target)
    MOVE.W  LM_X,D4
    MOVE.W  #8,D3
    LEA     PTR_LM,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE
    
    MOVE.B  #18,D0          
    TRAP    #15
    CMP.L   #1,D1
    BEQ     M_L
    CMP.L   #2,D1
    BEQ     M_R
    CMP.L   #3,D1
    BEQ     M_D
    BRA     DO_DOCK
M_L: SUBQ.W #5,CSM_X
    BRA DO_DOCK
M_R: ADDQ.W #5,CSM_X
    BRA DO_DOCK
M_D:
    MOVE.W  CSM_X,D0
    SUB.W   LM_X,D0
    BSR     ABS
    CMP.W   #5,D0
    BLE     D_OK
    BRA     DO_DOCK
D_OK:
    MOVE.B  #3,STATE
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 3: LANDING
*-------------------------------------------------------
DO_LAND:
    BSR     CLEAR_SCREEN
    ADDQ.W  #1,LAND_VY      ; Gravity
    MOVE.W  LAND_VY,D0
    ADD.W   D0,LAND_Y
    
    ; Draw Moon
    MOVE.W  #$1600,D1       ; Row 22
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SURFACE,A1
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.W  #25,D4          ; Center
    MOVE.W  LAND_Y,D3
    LEA     PTR_LM,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE

    CMP.W   #18,LAND_Y
    BGE     L_HIT

    LEA     LAND_KEYS,A1
    BSR     PRINT_INPUT_LINE
    MOVE.B  #18,D0
    TRAP    #15
    CMP.L   #1,D1
    BEQ     L_UP
    BRA     DO_LAND
L_UP: SUBI.W #4,LAND_VY
    BRA DO_LAND
L_HIT:
    CMP.W   #4,LAND_VY
    BLE     WIN
    LEA     CRASH_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    BRA     END_GAME
WIN:
    LEA     WIN_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    BRA     END_GAME

*-------------------------------------------------------
* RENDER ENGINE
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

DRAW_STARS:
    MOVE.W  #$0502,D1
    BSR     P_S
    MOVE.W  #$350A,D1
    BSR     P_S
    RTS
P_S: MOVE.B #11,D0
    TRAP #15
    LEA STAR,A1
    MOVE.B #14,D0
    TRAP #15
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

PRINT_STATUS_LINE:
    MOVE.W #$0000,D1
    MOVE.B #11,D0
    TRAP #15
    MOVE.B #14,D0
    TRAP #15
    RTS

PRINT_INPUT_LINE:
    MOVE.W #$0018,D1
    MOVE.B #11,D0
    TRAP #15
    MOVE.B #14,D0
    TRAP #15
    RTS

ABS: TST.W D0
    BPL A_X
    NEG.W D0
A_X: RTS

END_GAME:
    MOVE.B  #9,D0
    TRAP    #15

*-------------------------------------------------------
* DATA & SPRITES
*-------------------------------------------------------
STAR:       DC.B    '*',0
ALT_MSG:    DC.B    'ALTITUDE: ',0
PROMPT_LAUNCH: DC.B '1 + ENTER TO LAUNCH!',0
DOCK_MSG:   DC.B    'DOCK: 1=L, 2=R, 3=DOCK',0
LAND_KEYS:  DC.B    '1=THRUST: ',0
WIN_MSG:    DC.B    13,10,'SUCCESS!',0
CRASH_MSG:  DC.B    13,10,'CRASH!',0
SURFACE:    DC.B    '________________________________________________',0

PTR_SATURN: DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15
PTR_UPPER:  DC.L S1,S2,S3,S4,S5,S6,S14,S15
PTR_CSM:    DC.L C1,C2,C3,C4,C5
PTR_LM:     DC.L L1,L2,L3,L4,L5

S1:  DC.B '     ^     ',0
S2:  DC.B '    / \    ',0
S3:  DC.B '   |USA|   ',0
S4:  DC.B '   |   |   ',0
S5:  DC.B '   |   |   ',0
S6:  DC.B '   |---|   ',0
S7:  DC.B '   |   |   ',0
S8:  DC.B '   |   |   ',0
S9:  DC.B '   |---|   ',0
S10: DC.B '  /|   |\  ',0
S11: DC.B ' | |   | | ',0
S12: DC.B ' | |   | | ',0
S13: DC.B ' |_|___|_| ',0
S14: DC.B '  /     \  ',0
S15: DC.B ' ( V V V ) ',0

C1: DC.B '   /\   ',0
C2: DC.B '  /  \  ',0
C3: DC.B ' |    | ',0
C4: DC.B ' |____| ',0
C5: DC.B '  /__\  ',0

L1: DC.B '   __   ',0
L2: DC.B '  /  \  ',0
L3: DC.B ' [____] ',0
L4: DC.B '  |__|  ',0
L5: DC.B ' /    \ ',0

    END START