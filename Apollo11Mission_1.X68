*-----------------------------------------------------------
* Title      : Apollo 68K Mission
* Written by : Nazariy Buryak
* Date       : 18/02/2025
* Description: Apollo 11 Mission
*-----------------------------------------------------------

    ORG $1000

*-------------------------------------------------------
* CONSTANTS
*-------------------------------------------------------
PAD_STATE       EQU 0
FLY_STATE       EQU 1
DOCK_STATE      EQU 2
FLY_DOCKED      EQU 3
LAND_STAGE      EQU 4

LM_ROW          EQU 5
SPRITE_H        EQU 5

; Landing Module Unit (LMU) constants
LMU_START_X     EQU 70              ; Spawn in right corner of screen
LMU_START_Y     EQU 2               ; Start near top
GRAVITY         EQU 1               ; Gravity pull per frame
SURFACE_Y       EQU 28              ; Row where moon surface is
LANDING_ZONE_X1 EQU 9               ; Left edge of safe landing zone
LANDING_ZONE_X2 EQU 49              ; Right edge of safe landing zone
FRAME_DELAY     EQU 80
LM_WIDTH        EQU 8
LM_LAND_H       EQU 5               ; Height of landing LM sprite

STAGE0_FUEL     EQU 80              ; Fuel for stage 0 (full rocket)
STAGE1_FUEL     EQU 80              ; Fuel for stage 1 (upper stage)
STAGE2_FUEL     EQU 50              ; Fuel for stage 2 (coast to orbit)
SEP0_MIN_FUEL   EQU 10              ; Must have burned to at least this much remaining
SEP1_MIN_FUEL   EQU 10              ; Must have burned to at least this much remaining
LAND_FUEL_MAX   EQU 38              ; Landing fuel units

*-------------------------------------------------------
* VARIABLES
*-------------------------------------------------------
    ORG $4000

STATE:          DC.B    0
                DS.B    1           ; Padding for word alignment
ALT:            DC.W    0
CSM_X:          DC.W    10
OLD_CSM_X:      DC.W    10
CSM_Y:          DC.W    12
OLD_CSM_Y:      DC.W    12
LM_X:           DC.W    40
DOCKED_ALT:     DC.W    0
LANDING_INIT:   DC.W    0

; LMU physics variables
LMU_X:          DC.W    0           ; Current X position (column)
LMU_Y:          DC.W    0           ; Current Y position (row)
LMU_VX:         DC.W    0           ; Horizontal velocity
LMU_VY:         DC.W    0           ; Vertical velocity
OLD_LMU_X:      DC.W    0           ; Previous X for erasing
OLD_LMU_Y:      DC.W    0           ; Previous Y for erasing

PWD_BUF:        DS.B    8           ; scratch buffer for PRINT_WORD_DEC

; Fuel variables
FLY_INIT:       DC.W    0           ; 1 once FLY_STATE has been inited
FLY_FUEL:       DC.W    0           ; Phase 1 fuel remaining
LAND_FUEL:      DC.W    0           ; Landing fuel remaining
STAGE_SEP:      DC.W    0           ; 0=stage1 active, 1=upper stage flying
DISOBEYED:      DC.W    0           ; 1 if player ignored Houston warning
COAST_CTR:      DC.W    0           ; Frame counter for stage 2 disobey
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
    CMP.B   #LAND_STAGE,D0
    BEQ     DO_LANDING
    BRA     END_GAME

*-------------------------------------------------------
* PHASE 0: PRE-LAUNCH (PAD)
*-------------------------------------------------------
DO_PAD:
    BSR     CLEAR_SCREEN
    BSR     SHOW_STATS
    BSR     DRAW_STARS
    BSR     DRAW_PAD_ROCKET

    MOVE.W  #$0101,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     PROMPT_LAUNCH,A1
    MOVE.B  #14,D0
    TRAP    #15

PAD_WAIT:
    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     PAD_WAIT            ; no key yet - keep waiting
    MOVE.B  #5,D0
    TRAP    #15
    CMP.B   #'1',D1
    BNE     PAD_WAIT            ; wrong key - keep waiting

    BSR     CLEAR_SCREEN
    MOVE.B  #FLY_STATE,STATE
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 1: FLIGHT
* FLY_FUEL drains every frame in stages 0 and 1.
* Press 2 any time to separate:
*   fuel > threshold -> "Too early" warning, no action
*   fuel in valid window -> separation happens
*   fuel hits 0 before separating -> game over
*-------------------------------------------------------
DO_FLY:
    ; One-time init
    TST.W   FLY_INIT
    BNE     SKIP_FLY_INIT
    MOVE.W  #STAGE0_FUEL,FLY_FUEL
    CLR.W   STAGE_SEP
    CLR.W   DISOBEYED
    CLR.W   COAST_CTR
    MOVE.W  #1,FLY_INIT
    ; Draw rocket once (static - no need to redraw each frame)
    BSR     DRAW_STARS
    BSR     DRAW_FULL_ROCKET
    ; Show sep prompt once
    MOVE.W  #$0022,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SEP_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15

SKIP_FLY_INIT:
    ADDQ.W  #1,ALT

    MOVE.W  STAGE_SEP,D0
    CMP.W   #1,D0
    BEQ     FLY_STAGE1
    CMP.W   #2,D0
    BEQ     FLY_STAGE2

    ; ======= STAGE 0 =======
    SUBQ.W  #1,FLY_FUEL
    MOVE.W  FLY_FUEL,D0
    BLE     FLY_FUEL_OUT

    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     FLY_S0_DELAY
    MOVE.B  #5,D0
    TRAP    #15
    CMP.B   #'2',D1
    BNE     FLY_S0_DELAY

    ; Pressed '2' - check if in valid window
    MOVE.W  FLY_FUEL,D0
    CMP.W   #SEP0_MIN_FUEL,D0
    BLE     FLY_S0_DO_SEP
    ; Too early - Houston warning + choice
    MOVE.W  #$0024,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0025,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_OPT,A1
    MOVE.B  #14,D0
    TRAP    #15
FLY_S0_HWAIT:
    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     FLY_S0_HWAIT
    MOVE.B  #5,D0
    TRAP    #15
    CMP.B   #'1',D1
    BEQ     FLY_S0_DISOBEY         ; proceed despite Houston warning
    CMP.B   #'2',D1
    BEQ     FLY_S0_HBACK           ; keep flying
    BRA     FLY_S0_HWAIT           ; invalid key - ask again
FLY_S0_DISOBEY:
    MOVE.W  #1,DISOBEYED
    BRA     FLY_S0_DO_SEP
FLY_S0_HBACK:
    ; Clear warning rows and resume
    MOVE.W  #$0024,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0025,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    BRA     FLY_S0_DELAY

FLY_S0_DO_SEP:
    BSR     ERASE_ROCKET
    ; Clear prompt/warning rows
    MOVE.W  #$0022,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0024,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0025,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #1,STAGE_SEP
    MOVE.W  #STAGE1_FUEL,FLY_FUEL   ; reset fuel for stage 1
    ; Draw new stage rocket once
    BSR     DRAW_STARS
    BSR     DRAW_FIRST_SEP
    ; Show sep2 prompt once
    MOVE.W  #$0022,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SEP2_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15

FLY_S0_DELAY:
    BSR     SHOW_FLY_STATS
    MOVE.L  #4,D1
    MOVE.B  #23,D0
    TRAP    #15
    BRA     DO_FLY

    ; ======= STAGE 1 =======
FLY_STAGE1:
    SUBQ.W  #1,FLY_FUEL
    MOVE.W  FLY_FUEL,D0
    BLE     FLY_FUEL_OUT

    ; Non-blocking key check
    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     FLY_S1_DELAY
    MOVE.B  #5,D0
    TRAP    #15
    CMP.B   #'2',D1
    BNE     FLY_S1_DELAY

    ; Pressed '2' - check if in valid window
    MOVE.W  FLY_FUEL,D0
    CMP.W   #SEP1_MIN_FUEL,D0
    BLE     FLY_S1_DO_SEP
    ; Too early - Houston warning + choice
    MOVE.W  #$0024,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0025,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_OPT,A1
    MOVE.B  #14,D0
    TRAP    #15
FLY_S1_HWAIT:
    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     FLY_S1_HWAIT
    MOVE.B  #5,D0
    TRAP    #15
    CMP.B   #'1',D1
    BEQ     FLY_S1_DISOBEY         ; proceed despite Houston warning
    CMP.B   #'2',D1
    BEQ     FLY_S1_HBACK           ; keep flying
    BRA     FLY_S1_HWAIT           ; invalid key - ask again
FLY_S1_DISOBEY:
    MOVE.W  #1,DISOBEYED
    BRA     FLY_S1_DO_SEP
FLY_S1_HBACK:
    ; Clear warning rows and resume
    MOVE.W  #$0024,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0025,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    BRA     FLY_S1_DELAY

FLY_S1_DO_SEP:
    BSR     ERASE_FIRST_SEP
    ; Clear prompt/warning rows
    MOVE.W  #$0022,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0024,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0025,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #2,STAGE_SEP
    MOVE.W  #STAGE2_FUEL,FLY_FUEL   ; reset fuel for stage 2
    ; Draw new stage rocket once
    BSR     DRAW_STARS
    BSR     DRAW_SECOND_SEP

FLY_S1_DELAY:
    BSR     SHOW_FLY_STATS
    MOVE.L  #4,D1
    MOVE.B  #23,D0
    TRAP    #15
    BRA     DO_FLY

    ; ======= STAGE 2  =======
FLY_STAGE2:
    ; Check if player disobeyed Houston
    TST.W   DISOBEYED
    BEQ     FLY_S2_OK
    ADDQ.W  #1,COAST_CTR
    MOVE.W  COAST_CTR,D0
    CMP.W   #60,D0
    BGE     FLY_DISOBEY_FAIL
FLY_S2_OK:
    SUBQ.W  #1,FLY_FUEL
    MOVE.W  FLY_FUEL,D0
    BLE     FLY_FUEL_OUT

    MOVE.W  ALT,D0
    CMP.W   #180,D0
    BGE     FLY_GO_DOCK
    BSR     SHOW_FLY_STATS
    MOVE.L  #4,D1
    MOVE.B  #23,D0
    TRAP    #15
    BRA     DO_FLY

FLY_GO_DOCK:
    BSR     CLEAR_SCREEN
    CLR.W   FLY_INIT
    CLR.W   STAGE_SEP
    MOVE.B  #DOCK_STATE,STATE
    BRA     MAIN_LOOP

FLY_FUEL_OUT:
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     FLY_FUEL_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    ; Wait for any key
    MOVE.B  #5,D0
    TRAP    #15
    BRA     END_GAME

FLY_DISOBEY_FAIL:
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     DISOBEY_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.B  #5,D0
    TRAP    #15
    BRA     END_GAME

*-------------------------------------------------------
* PHASE 2: DOCKING
*-------------------------------------------------------
DO_DOCK:
    BSR     CLEAR_SCREEN
    BSR     SHOW_STATS

    ; Draw LM once (static)
    MOVE.W  LM_X,D4
    MOVE.W  #LM_ROW,D3
    LEA     PTR_LM_UP,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE

    ; Draw CSM at initial position
    MOVE.W  CSM_X,D4
    MOVE.W  CSM_Y,D3
    LEA     PTR_CSM,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE

    ; Print DOCK_MSG once
    MOVE.W  #$1500,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     DOCK_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15

DOCK_LOOP:
    ; Non-blocking key read for docking
    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     DOCK_NO_KEY         ; no key - just delay
    ; Move cursor to safe spot before reading (task 5 echoes)
    MOVE.W  #$0018,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #5,D0
    TRAP    #15                 ; D1.B = ASCII char
    MOVE.B  D1,D2              ; SAVE key in D2 before clobbering D1
    ; Erase the echoed character
    MOVE.W  #$0018,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANK_SMALL,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.B  D2,D1              ; RESTORE key from D2

    ; Save old position before moving
    MOVE.W  CSM_X,OLD_CSM_X
    MOVE.W  CSM_Y,OLD_CSM_Y

    CMP.B   #'1',D1
    BEQ     M_U
    CMP.B   #'2',D1
    BEQ     M_S
    CMP.B   #'3',D1
    BEQ     M_L
    CMP.B   #'4',D1
    BEQ     M_R
    CMP.B   #'5',D1
    BEQ     M_D

DOCK_NO_KEY:
    ; Frame delay
    MOVE.L  #8,D1
    MOVE.B  #23,D0
    TRAP    #15
    BRA     DOCK_LOOP

M_L:
    SUBQ.W  #2,CSM_X
    BRA     DOCK_MOVED
M_R:
    ADDQ.W  #2,CSM_X
    BRA     DOCK_MOVED
M_U:
    SUBQ.W  #1,CSM_Y
    BRA     DOCK_MOVED
M_S:
    ADDQ.W  #1,CSM_Y
    BRA     DOCK_MOVED

DOCK_MOVED:
    ; --- Collision check: CSM vs LM bounding boxes ---
    ; LM: cols LM_X..LM_X+7, rows LM_ROW..LM_ROW+4
    ; CSM: cols CSM_X..CSM_X+7, rows CSM_Y..CSM_Y+4
    ; Horizontal: CSM_X+8 <= LM_X  -> no overlap
    MOVE.W  CSM_X,D0
    ADD.W   #8,D0
    CMP.W   LM_X,D0
    BLE     DOCK_NO_COLL
    ; Horizontal: LM_X+8 <= CSM_X  -> no overlap
    MOVE.W  LM_X,D0
    ADD.W   #8,D0
    CMP.W   CSM_X,D0
    BLE     DOCK_NO_COLL
    ; Vertical: CSM_Y+5 <= LM_ROW  -> no overlap
    MOVE.W  CSM_Y,D0
    ADD.W   #SPRITE_H,D0
    CMP.W   #LM_ROW,D0
    BLE     DOCK_NO_COLL
    ; Vertical: LM_ROW+5 <= CSM_Y  -> no overlap (CSM below LM = valid approach)
    MOVE.W  #LM_ROW,D0
    ADD.W   #SPRITE_H,D0
    CMP.W   CSM_Y,D0
    BLE     DOCK_NO_COLL
    ; COLLISION - Houston we have a problem!
    BRA     DOCK_CRASH
DOCK_NO_COLL:
    ; Erase old CSM
    BSR     ERASE_CSM
    ; Draw CSM at new position
    MOVE.W  CSM_X,D4
    MOVE.W  CSM_Y,D3
    LEA     PTR_CSM,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE
    ; Redraw LM in case CSM erased part of it
    MOVE.W  LM_X,D4
    MOVE.W  #LM_ROW,D3
    LEA     PTR_LM_UP,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE
    BRA     DOCK_NO_KEY
M_D:
    ; Check X alignment
    MOVE.W  CSM_X,D0
    SUB.W   LM_X,D0
    BSR     ABS
    CMP.W   #3,D0
    BGT     DOCK_LOOP
    ; Check Y alignment
    MOVE.W  CSM_Y,D0
    SUB.W   #LM_ROW+5,D0
    BSR     ABS
    CMP.W   #1,D0
    BGT     DOCK_LOOP
D_OK:
    CLR.W   DOCKED_ALT
    MOVE.B  #FLY_DOCKED,STATE
    BRA     MAIN_LOOP

DOCK_CRASH:
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_PROB,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.B  #5,D0
    TRAP    #15
    BRA     END_GAME

*-------------------------------------------------------
* PHASE 3: JOINT FLIGHT (DOCKED)
*-------------------------------------------------------
DO_FLY_DOCKED:
    TST.W   DOCKED_ALT
    BNE     DFD_SKIP_CLEAR
    BSR     CLEAR_SCREEN
DFD_SKIP_CLEAR:
    ; Blank hint row every frame to wipe any stale content
    MOVE.W  #$1500,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
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
    BGE     GO_LAND
    BRA     DO_FLY_DOCKED

GO_LAND:
    BSR     CLEAR_SCREEN
    MOVE.B  #LAND_STAGE,STATE
    BRA     MAIN_LOOP

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
    LEA     BLANK_SMALL,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     EJ_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-------------------------------------------------------
* PHASE 4: LUNAR LANDING
*-------------------------------------------------------
DO_LANDING:
    ; One-time initialisation
    TST.W   LANDING_INIT
    BNE     SKIP_LANDING_INIT
    BSR     CLEAR_SCREEN
    BSR     DRAW_MOON_SURFACE       ; Draw ASCII moon background once
    BSR     INIT_LMU_LANDING
    MOVE.W  #1,LANDING_INIT
SKIP_LANDING_INIT:

    ; Save position BEFORE input so ERASE_LMU always covers the last drawn frame
    MOVE.W  LMU_X,OLD_LMU_X
    MOVE.W  LMU_Y,OLD_LMU_Y
    BSR     READ_LANDING_INPUT
    BSR     ERASE_LMU
    BSR     UPDATE_LMU
    BSR     DRAW_LMU
    BSR     SHOW_LANDING_STATS
    BSR     CHECK_LANDING

    ; Frame delay controls game speed / gravity feel
    MOVE.L  #FRAME_DELAY,D1
    MOVE.B  #23,D0
    TRAP    #15

    BRA     DO_LANDING

READ_LANDING_INPUT:
    MOVEM.L D0-D1,-(A7)

    ; Non-blocking key check
    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     LAND_DONE           ; no key - skip
    MOVE.B  #5,D0
    TRAP    #15                 ; D1.B = ASCII char

    CMP.B   #'w',D1
    BEQ     LAND_THRUST
    CMP.B   #'W',D1
    BEQ     LAND_THRUST
    CMP.B   #'a',D1
    BEQ     LAND_LEFT
    CMP.B   #'A',D1
    BEQ     LAND_LEFT
    CMP.B   #'d',D1
    BEQ     LAND_RIGHT
    CMP.B   #'D',D1
    BEQ     LAND_RIGHT
    BRA     LAND_DONE

LAND_THRUST:
    MOVE.W  LAND_FUEL,D0
    BEQ     LAND_DONE           ; no fuel left - thrust disabled, fall and crash
    SUBQ.W  #1,LAND_FUEL        ; consume one unit
    SUB.W   #3,LMU_VY           ; apply upward impulse
    BRA     LAND_DONE

LAND_LEFT:
    SUB.W   #1,LMU_VX        ; apply leftward velocity impulse
    CMP.W   #-4,LMU_VX
    BGE     LAND_DONE
    MOVE.W  #-4,LMU_VX       ; clamp
    BRA     LAND_DONE

LAND_RIGHT:
    ADD.W   #1,LMU_VX        ; apply rightward velocity impulse
    CMP.W   #4,LMU_VX
    BLE     LAND_DONE
    MOVE.W  #4,LMU_VX        ; clamp
    BRA     LAND_DONE

LAND_DONE:
    MOVEM.L (A7)+,D0-D1
    RTS
*-------------------------------------------------------
* INIT_LMU_LANDING
* Resets the LMU to starting position with zero velocity.
*-------------------------------------------------------
INIT_LMU_LANDING:
    MOVE.W  #LMU_START_X,LMU_X
    MOVE.W  #LMU_START_Y,LMU_Y
    MOVE.W  #LMU_START_X,OLD_LMU_X
    MOVE.W  #LMU_START_Y,OLD_LMU_Y
    CLR.W   LMU_VX
    CLR.W   LMU_VY
    MOVE.W  #LAND_FUEL_MAX,LAND_FUEL    ; fill landing tank
    RTS

*-------------------------------------------------------
* UPDATE_LMU
*-------------------------------------------------------
UPDATE_LMU:
    MOVEM.L D0,-(A7)

    ; Apply gravity every frame
    ADD.W   #GRAVITY,LMU_VY

    ; Terminal velocity (capped at 3 for playability)
    MOVE.W  LMU_VY,D0
    CMP.W   #3,D0
    BLE     UL_NO_CLAMP_V
    MOVE.W  #3,LMU_VY
UL_NO_CLAMP_V:

    ; Update vertical position
    MOVE.W  LMU_VY,D0
    ADD.W   D0,LMU_Y

    ; Prevent going above screen
    MOVE.W  LMU_Y,D0
    CMP.W   #0,D0
    BGE     UL_HORIZ
    CLR.W   LMU_Y
    CLR.W   LMU_VY

UL_HORIZ:
    ; Apply horizontal velocity
    MOVE.W  LMU_VX,D0
    ADD.W   D0,LMU_X

    ; Horizontal friction: drift toward zero by 1 each frame
    TST.W   LMU_VX
    BEQ     UL_DONE
    BPL     UL_VX_POS
    ADDQ.W  #1,LMU_VX       ; negative VX: nudge toward 0
    BRA     UL_DONE
UL_VX_POS:
    SUBQ.W  #1,LMU_VX       ; positive VX: nudge toward 0

UL_DONE:
    MOVEM.L (A7)+,D0
    RTS
*-------------------------------------------------------
* DRAW_MOON_SURFACE
*-------------------------------------------------------
DRAW_MOON_SURFACE:
    MOVEM.L D0-D4/A0-A1,-(A7)

    ; Draw space (stars) rows 3-25
    MOVE.W  #3,D3
MS_SPACE_L:
    MOVE.W  #0,D4
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0


    TRAP    #15
    LEA     SPACE_LINE,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    CMP.W   #27,D3
    BLT     MS_SPACE_L

    ; Draw surface row 33 (top of terrain)
    MOVE.W  #33,D3
    MOVE.W  #0,D4
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SURFACE_TOP,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Draw solid moon rows 35-38
    MOVE.W  #34,D3
MS_GROUND_L:
    MOVE.W  #0,D4
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     GROUND_LINE,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    CMP.W   #38,D3
    BLT     MS_GROUND_L

    ; Also draw a couple of stars manually
    MOVE.W  #$0308,D1
    BSR     P_S
    MOVE.W  #$1503,D1
    BSR     P_S
    MOVE.W  #$4A06,D1
    BSR     P_S
    MOVE.W  #$300B,D1
    BSR     P_S

    MOVEM.L (A7)+,D0-D4/A0-A1
    RTS
*-------------------------------------------------------
* DRAW_LMU
* Draws the Lunar Module at current LMU_X, LMU_Y.
* Uses TRAP #15 task 11 (cursor position) + task 14 (print).
*-------------------------------------------------------
DRAW_LMU:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  LMU_X,D4
    MOVE.W  LMU_Y,D3
    LEA     PTR_LM_LAND,A0
    MOVE.W  #LM_LAND_H,D2
    BSR     DRAW_SPRITE
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-------------------------------------------------------
* ERASE_LMU
* Blanks the LMU sprite at OLD_LMU_X, OLD_LMU_Y.
*-------------------------------------------------------
ERASE_LMU:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  OLD_LMU_X,D4
    MOVE.W  OLD_LMU_Y,D3
    MOVE.W  #LM_LAND_H,D2
ELU_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANK_SMALL,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ELU_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

SHOW_LANDING_STATS:
    MOVEM.L D0-D1,-(A7)

    ; --- Row 0: Controls ---
    MOVE.W  #$0000,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     LAND_CTRL_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; --- Row 1: VY / X ---
    MOVE.W  #$0001,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.W  #$0001,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     VY_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  LMU_VY,D1
    BSR     PRINT_WORD_DEC
    LEA     X_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  LMU_X,D1
    BSR     PRINT_WORD_DEC

    ; --- Row 2: FUEL ---
    MOVE.W  #$0002,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.W  #$0002,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     FUEL_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  LAND_FUEL,D1
    BSR     PRINT_WORD_DEC

    MOVEM.L (A7)+,D0-D1
    RTS

*-------------------------------------------------------
* CHECK_LANDING
* Checks if LMU has reached SURFACE_Y.
* If within landing zone and slow enough -> success.
* Otherwise -> crash.
*-------------------------------------------------------
CHECK_LANDING:
    MOVEM.L D0-D1,-(A7)

    ; Calculate bottom of LMU
    MOVE.W  LMU_Y,D0
    ADD.W   #LM_LAND_H,D0  
    
    CMP.W   #SURFACE_Y,D0
    BLT     CL_DONE

    ; Clamp to surface so it doesn't sink
    MOVE.W  #SURFACE_Y,D0
    SUB.W   #LM_LAND_H,D0
    MOVE.W  D0,LMU_Y

    ; --- TOUCHDOWN REACHED ---
    MOVE.W  LMU_VY,D1
    CMP.W   #2,D1
    BGT     CL_CRASH        ; Too fast! Crash.

    MOVE.W  LMU_X,D0

    ; Left edge check
    CMP.W   #LANDING_ZONE_X1,D0
    BLT     CL_CRASH

    ; Right edge check
    MOVE.W  #LANDING_ZONE_X2,D1
    SUB.W   #LM_WIDTH,D1       ; make sure right side of LM fits
    CMP.W   D1,D0
    BGT     CL_CRASH

    ; --- SUCCESS ---
    MOVEM.L (A7)+, D0-D1
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     LAND_SUCCESS,A1
    MOVE.B  #14,D0
    TRAP    #15
    ; Wait for any key
    MOVE.B  #5,D0
    TRAP    #15
    BRA     CL_END_GAME

CL_CRASH:
    MOVEM.L (A7)+, D0-D1
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     LAND_CRASH,A1
    MOVE.B  #14,D0
    TRAP    #15
    BRA     CL_END_GAME

CL_END_GAME:
    BRA     END_GAME

CL_DONE:
    MOVEM.L (A7)+,D0-D1
    RTS
*-------------------------------------------------------
* RENDERING SUBROUTINES
*-------------------------------------------------------
; Phase 0 pad rocket: (no flames), col=30, row=3
DRAW_PAD_ROCKET:
    LEA     PTR_SAT_PAD,A0
    MOVE.W  #32,D2          ; rows visible on screen (full rocket)
    MOVE.W  #1,D3           ; start row
    MOVE.W  #30,D4          ; column
    BSR     DRAW_SPRITE
    RTS

; Phase 1 full rocket: (with flames), col=30, row=1
DRAW_FULL_ROCKET:
    LEA     PTR_SATURN,A0
    MOVE.W  #33,D2          ; rows visible on screen (S1-S33, full rocket+flames)
    MOVE.W  #1,D3           ; start row
    MOVE.W  #30,D4          ; column
    BSR     DRAW_SPRITE
    RTS

; Phase 1 stage 1 sep: S2-S17+S32-S33 (upper stage+engine), col=30, row=0
DRAW_FIRST_SEP:
    LEA     PTR_FIRST_SEP,A0
    MOVE.W  #18,D2
    MOVE.W  #1,D3
    MOVE.W  #30,D4
    BSR     DRAW_SPRITE
    RTS

; Phase 1 stage 2 sep: col=30, row=1
DRAW_SECOND_SEP:
    LEA     PTR_SECOND_SEP,A0
    MOVE.W  #14,D2
    MOVE.W  #1,D3
    MOVE.W  #30,D4
    BSR     DRAW_SPRITE
    RTS

*-------------------------------------------------------
* DRAW_SPRITE
* D4 = column, D3 = starting row, D2 = number of rows
* A0 = pointer table (each entry is a DC.L to a string)
*-------------------------------------------------------
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

; Erase full rocket area (col=30, row=1, 34 rows to cover 33-row rocket + buffer)
ERASE_ROCKET:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #30,D4
    MOVE.W  #1,D3
    MOVE.W  #34,D2
    LEA     BLANK_ROCKET,A1
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

; Erase first sep area (col=30, row=1, 19 rows ? matches DRAW_FIRST_SEP row=1+18 +1 buffer)
ERASE_FIRST_SEP:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #30,D4
    MOVE.W  #1,D3
    MOVE.W  #19,D2
    LEA     BLANK_ROCKET,A1
ER_F_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_F_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

; Erase second sep area (col=30, row=1, 15 rows ? matches DRAW_SECOND_SEP row=1+14 +1 buffer)
ERASE_SECOND_SEP:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #30,D4
    MOVE.W  #1,D3
    MOVE.W  #15,D2
    LEA     BLANK_ROCKET,A1
ER_S_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_S_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

ERASE_CSM:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  OLD_CSM_X,D4
    MOVE.W  OLD_CSM_Y,D3
    MOVE.W  #SPRITE_H,D2
    LEA     BLANK_SMALL,A1
ER_CSM_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_CSM_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

DRAW_STARS:
    MOVE.W  #$0502,D1
    BSR     P_S

    MOVE.W  #$350A,D1
    BSR     P_S
    
    MOVE.W  #$2204,D1
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

*-------------------------------------------------------
* SHOW_FLY_STATS
* Shows ALTITUDE and FLY_FUEL at top-left (row 0, col 0).
*-------------------------------------------------------
SHOW_FLY_STATS:
    MOVEM.L D0-D1,-(A7)
    ; Blank row 0 stats area
    MOVE.W  #$0000,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    ; Print ALT:
    MOVE.W  #$0000,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     ALT_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  ALT,D1
    BSR     PRINT_WORD_DEC
    ; Print FUEL:
    LEA     FLY_FUEL_LBL,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  FLY_FUEL,D1
    BSR     PRINT_WORD_DEC
    MOVEM.L (A7)+,D0-D1
    RTS

SHOW_STATS:
    MOVEM.L D0-D1,-(A7)
    ; Blank row 20 first to prevent stale text from previous phases
    MOVE.W  #$0014,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    ; Reposition and print altitude
    MOVE.W  #$0014,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     ALT_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  ALT,D1
    BSR     PRINT_WORD_DEC
    MOVEM.L (A7)+,D0-D1
    RTS

ABS:
    TST.W   D0
    BPL     A_X
    NEG.W   D0
A_X:
    RTS

*-------------------------------------------------------
* PRINT_WORD_DEC
* Prints D1.W as a signed decimal to the display at the
* current cursor position using Task 14 only.
* Modifies D0-D4, A1 (all saved/restored).
*-------------------------------------------------------
PRINT_WORD_DEC:
    MOVEM.L D0-D4/A1,-(A7)

    ; Build string right-to-left in PWD_BUF
    LEA     PWD_BUF+7,A1
    MOVE.B  #0,(A1)         ; null terminator

    ; Track sign
    MOVE.W  D1,D2
    CLR.B   D3              ; D3=0: positive
    TST.W   D2
    BPL     PWD_POS
    NEG.W   D2
    MOVE.B  #1,D3           ; D3=1: negative
PWD_POS:
    ; Special case: value is zero
    CMP.W   #0,D2
    BNE     PWD_DIGITS
    SUBQ.L  #1,A1
    MOVE.B  #'0',(A1)
    BRA     PWD_SIGN

PWD_DIGITS:
    ; Extract digits least-significant first
PWD_DIG_LOOP:
    CLR.L   D4
    MOVE.W  D2,D4           ; zero-extend to long for DIVU
    DIVU    #10,D4          ; quotient in low word, remainder in high word
    MOVE.W  D4,D2           ; save quotient
    SWAP    D4              ; remainder now in low word
    ADD.B   #'0',D4         ; convert to ASCII digit
    SUBQ.L  #1,A1
    MOVE.B  D4,(A1)         ; store digit
    TST.W   D2
    BNE     PWD_DIG_LOOP    ; more digits?

PWD_SIGN:
    TST.B   D3
    BEQ     PWD_PRINT
    SUBQ.L  #1,A1
    MOVE.B  #'-',(A1)       ; prepend minus sign

PWD_PRINT:
    MOVE.B  #14,D0
    TRAP    #15             ; print string at cursor pos on display
    MOVEM.L (A7)+,D0-D4/A1
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
DOCK_MSG:       DC.B    'Move: 1=Up 2=Dw 3=Lt 4=Rt 5=Dock',0
BLANKLINE_WIDE: DC.B    '                                                                          ',0
VY_MSG:         DC.B    'VY:',0
X_MSG:          DC.B    '  X:',0
FUEL_MSG:       DC.B    'FUEL:',0
FLY_FUEL_LBL:   DC.B    '  FUEL:',0
SEP_MSG:        DC.B    'Press 2 to separate stage 1!   ',0
SEP2_MSG:       DC.B    'Press 2 to separate stage 2!   ',0
HOUSTON_MSG:    DC.B    'Eagle its Houston, do not proceed with early separation!',0
HOUSTON_OPT:    DC.B    '1=Proceed  2=Keep Flying',0
DISOBEY_MSG:    DC.B    'Insufficient altitude - Mission Failed',0
FLY_FUEL_MSG:   DC.B    '*** OUT OF FUEL! MISSION FAILED ***',0
LAND_SUCCESS:   DC.B    '*** EAGLE HAS LANDED! ***',0
LAND_CRASH:     DC.B    '*** CRASH LANDING! MISSION FAILED ***',0
HOUSTON_PROB:   DC.B    'Houston, we have a problem!',0
BLANK_ROCKET:   DC.B    '                ',0
BLANK_SMALL:    DC.B    '          ',0
LAND_CTRL_MSG:  DC.B    'W=Thrust  A=Left  D=Right',0
SPACE_LINE:  DC.B '                                                                                ',0
SURFACE_TOP: DC.B '~~~~\/\/\________________________________________/\/\/\/\/\/\/\/\/\/\/\/\/\/~~~~',0
GROUND_LINE: DC.B '################################################################################',0

; Sprite pointer tables
; Full rocket with flames (S1-S33, phase 1 stage 0)
PTR_SATURN:    DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15,S16,S17,S18,S19,S20,S21,S22,S23,S24,S25,S26,S27,S28,S29,S30,S31,S32,S33
; Pad rocket without flames (S1-S32, phase 0)
PTR_SAT_PAD:   DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15,S16,S17,S18,S19,S20,S21,S22,S23,S24,S25,S26,S27,S28,S29,S30,S31,S32
; First separation: upper stage S2-S17 + engine flames S32-S33
PTR_FIRST_SEP: DC.L S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15,S16,S17,S32,S33
; Second separation: CSM capsule S2-S13 + flames
PTR_SECOND_SEP: DC.L S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S34,S35
PTR_CSM:     DC.L C1,C2,C3,C4,C5
PTR_CSM_FLY: DC.L C1,C2,C3,C4,C5,C6
PTR_LM_UP:   DC.L U1,U2,U3,U4,U5
PTR_LM_LAND: DC.L L1,L2,L3,L4,L5

S1:  DC.B '       |       ',0
S2:  DC.B '       !       ',0
S3:  DC.B '      / \      ',0
S4:  DC.B '      [ ]      ',0
S5:  DC.B '     /   \     ',0
S6:  DC.B '     |   |     ',0
S7:  DC.B '     |   |     ',0
S8:  DC.B '     |___|     ',0
S9:  DC.B '    /__|__\    ',0
S10: DC.B '    |     |    ',0
S11: DC.B '    |     |    ',0
S12: DC.B '    |     |    ',0
S13: DC.B '    |_____|    ',0
S14: DC.B '   /       \   ',0
S15: DC.B '   |       |   ',0
S16: DC.B '   |_______|   ',0
S17: DC.B '   | |   | |   ',0
S18: DC.B '   | |   | |   ',0
S19: DC.B '   |_|   |_|   ',0
S20: DC.B '   |       |   ',0
S21: DC.B '   |       |   ',0
S22: DC.B '   |       |   ',0
S23: DC.B '   |       |   ',0
S24: DC.B '   |       |   ',0
S25: DC.B '   |_     _|   ',0
S26: DC.B '   | | U | |   ',0
S27: DC.B '   | | S | |   ',0
S28: DC.B '   | | A | |   ',0
S29: DC.B '   | |   | |   ',0
S30: DC.B '  /| |   | |\  ',0
S31: DC.B ' |_|_|___|_|_| ',0
S32: DC.B '    /\/|\/\    ',0
S33: DC.B '    VVVVVVV    ',0
S34: DC.B '      /|\      ',0
S35: DC.B '      VVV      ',0

C1: DC.B '   /\   ',0
C2: DC.B '  /__\  ',0
C3: DC.B ' |+  +| ',0
C4: DC.B ' [____] ',0
C5: DC.B '  /__\  ',0
C6: DC.B '   VV   ',0

U1: DC.B ' \ __ / ',0
U2: DC.B ' _|__|_ ',0
U3: DC.B ' [    ] ',0
U4: DC.B '  \__/  ',0
U5: DC.B '   ''   ',0

L1: DC.B '   __   ',0 
L2: DC.B '  /  \  ',0
L3: DC.B ' [____] ',0
L4: DC.B '  |__|  ',0
L5: DC.B ' / vv \ ',0

    END START

*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~

*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
